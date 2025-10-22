#!/usr/bin/env bash
# Quality Gate Hook
# Evaluates mission outputs before finalization.
# Emits a machine-readable report and exits non-zero if thresholds fail.

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$HOOK_DIR/../../.." && pwd)"

# Source core helpers with fallback (hooks must never fail)
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/core-helpers.sh" 2>/dev/null || {
    # Minimal fallbacks if core-helpers unavailable
    get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
    require_command() { command -v "$1" >/dev/null 2>&1 || { echo "$1 is required" >&2; return 1; }; }
    log_error() { echo "Error: $*" >&2; }
}

# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/config-loader.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/error-messages.sh" 2>/dev/null || true

# Check required dependencies
require_command "python3" || {
    log_error "python3 is required for trust and recency calculations"
    exit 1
}

require_command "bc" || {
    log_error "bc is required for threshold comparisons"
    exit 1
}

SESSION_DIR="${1:-${CCONDUCTOR_SESSION_DIR:-}}"
if [[ -z "$SESSION_DIR" ]]; then
    echo "quality-gate: session directory not provided" >&2
    exit 1
fi

if [[ ! -d "$SESSION_DIR" ]]; then
    echo "quality-gate: session directory not found: $SESSION_DIR" >&2
    exit 1
fi

KG_FILE="$SESSION_DIR/knowledge-graph.json"
if [[ ! -f "$KG_FILE" ]]; then
    echo "quality-gate: knowledge graph missing at $KG_FILE" >&2
    exit 1
fi

CONFIG_JSON="$(load_config "quality-gate")"

# Operating mode (advisory|enforce)
MODE=$(echo "$CONFIG_JSON" | jq -r '.mode // "advisory"' | tr '[:upper:]' '[:lower:]')
if [[ "$MODE" != "advisory" && "$MODE" != "enforce" ]]; then
    MODE="advisory"
fi

# Thresholds
MIN_SOURCES_PER_CLAIM=$(echo "$CONFIG_JSON" | jq -r '.thresholds.min_sources_per_claim // 1')
MIN_INDEPENDENT_SOURCES=$(echo "$CONFIG_JSON" | jq -r '.thresholds.min_independent_sources // 1')
MIN_TRUST_SCORE=$(echo "$CONFIG_JSON" | jq -r '.thresholds.min_trust_score // 0')
MIN_CLAIM_CONFIDENCE=$(echo "$CONFIG_JSON" | jq -r '.thresholds.min_claim_confidence // 0')
MAX_LOW_CONFIDENCE_CLAIMS=$(echo "$CONFIG_JSON" | jq -r '.thresholds.max_low_confidence_claims // 0')
MAX_UNRESOLVED_CONTRADICTIONS=$(echo "$CONFIG_JSON" | jq -r '.thresholds.max_unresolved_contradictions // 0')

# Recency settings
RECENCY_ENFORCE=$(echo "$CONFIG_JSON" | jq -r '.recency.enforce // false')
MAX_SOURCE_AGE_DAYS=$(echo "$CONFIG_JSON" | jq -r '.recency.max_source_age_days // 0')
ALLOW_UNPARSED_DATES=$(echo "$CONFIG_JSON" | jq -r '.recency.allow_unparsed_dates // true')

# Trust weights
TRUST_WEIGHTS_LIST=$(echo "$CONFIG_JSON" | jq -r '.trust_weights // {} | to_entries[] | "\(.key)\t\(.value)"')
DEFAULT_TRUST_WEIGHT=$(echo "$CONFIG_JSON" | jq -r '.default_trust_weight // 0')

OUTPUT_FILENAME=$(echo "$CONFIG_JSON" | jq -r '.reporting.output_filename // "artifacts/quality-gate.json"')
OUTPUT_PATH="$SESSION_DIR/$OUTPUT_FILENAME"
OUTPUT_DIR="$(dirname "$OUTPUT_PATH")"
mkdir -p "$OUTPUT_DIR"
SUMMARY_FILENAME=$(echo "$CONFIG_JSON" | jq -r '.reporting.summary_filename // "artifacts/quality-gate-summary.json"')
SUMMARY_PATH="$SESSION_DIR/$SUMMARY_FILENAME"

# Use get_timestamp from core-helpers (fallback provided above)

normalize_domain() {
    local url="$1"
    if [[ -z "$url" || "$url" == "null" ]]; then
        echo ""
        return
    fi
    local cleaned="${url#*://}"
    cleaned="${cleaned%%/*}"
    cleaned="${cleaned#www.}"
    echo "$cleaned"
}

lookup_trust_weight() {
    local label="$1"
    local weight
    weight=$(printf '%s\n' "$TRUST_WEIGHTS_LIST" | awk -F'\t' -v key="$label" 'BEGIN{found=0} $1 == key {print $2; found=1; exit} END{if(found==0) printf ""}')
    if [[ -z "$weight" ]]; then
        weight="$DEFAULT_TRUST_WEIGHT"
    fi
    echo "$weight"
}

parse_source_age() {
    local raw_date="$1"
    if [[ -z "$raw_date" || "$raw_date" == "null" ]]; then
        return 1
    fi
    python3 - "$raw_date" <<'PY'
import sys
from datetime import datetime, timezone

raw = sys.argv[1].strip()
if not raw:
    sys.exit(1)

formats = [
    "%Y-%m-%d",
    "%Y/%m/%d",
    "%Y-%m",
    "%Y/%m",
    "%Y",
    "%b %d %Y",
    "%b %Y",
    "%B %d %Y",
    "%B %Y"
]

now = datetime.now(timezone.utc).date()

def iso_parse(value: str):
    cleaned = value.strip()
    if cleaned.endswith("Z"):
        cleaned = cleaned[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(cleaned)
    except ValueError:
        return None
    return dt.date()

parsed = iso_parse(raw)
if parsed is None:
    for fmt in formats:
        try:
            dt = datetime.strptime(raw, fmt)
        except ValueError:
            continue
        if hasattr(dt, "date"):
            parsed = dt.date()
        else:
            parsed = dt
        break

if parsed is None:
    sys.exit(2)

# Heuristic: for year-only dates, assume mid-year (July 1) to avoid
# over-penalizing sources that only publish coarse dates.
if raw.isdigit() and len(raw) == 4:
    parsed = parsed.replace(month=7, day=1)

age_days = (now - parsed).days
print(age_days)
PY
    local status=$?
    if [[ $status -ne 0 ]]; then
        return 1
    fi
    return 0
}

tmp_claims="$(mktemp)"
tmp_session="$(mktemp)"
trap 'rm -f "$tmp_claims" "$tmp_session"' EXIT

total_claims=$(jq '.claims | length' "$KG_FILE")
failed_claims=0
low_confidence_claims=0
total_trust_score=0
trust_score_count=0

while IFS= read -r claim_json; do
    claim_id=$(echo "$claim_json" | jq -r '.id // "unknown"')
    statement=$(echo "$claim_json" | jq -r '.statement // ""')
    confidence=$(echo "$claim_json" | jq -r '.confidence // 0')
    sources_count=$(echo "$claim_json" | jq '.sources // [] | length')
    domains_seen=""
    unique_domains=0
    trust_score=0
    oldest_source_days=""
    newest_source_days=""
    parseable_dates=0
    unparsed_dates=0

    while IFS=$'\t' read -r credibility url date_str; do
        [[ "$credibility" == "null" ]] && credibility="unknown"
        [[ -z "$credibility" ]] && credibility="unknown"
        [[ "$url" == "null" ]] && url=""
        [[ "$date_str" == "null" ]] && date_str=""

        weight="$(lookup_trust_weight "$credibility")"
        trust_score=$(python3 - <<PY
from decimal import Decimal
print((Decimal("$trust_score") + Decimal("$weight")).quantize(Decimal("0.0001")))
PY
)

        domain=$(normalize_domain "$url")
        if [[ -n "$domain" ]]; then
            case " $domains_seen " in
                *" $domain "*) ;;
                *)
                    domains_seen+=" $domain"
                    unique_domains=$((unique_domains + 1))
                    ;;
            esac
        fi

        if [[ "$RECENCY_ENFORCE" == "true" ]]; then
            if age=$(parse_source_age "$date_str"); then
                parseable_dates=$((parseable_dates + 1))
                if [[ -z "$oldest_source_days" || "$age" -gt "$oldest_source_days" ]]; then
                    oldest_source_days="$age"
                fi
                if [[ -z "$newest_source_days" || "$age" -lt "$newest_source_days" ]]; then
                    newest_source_days="$age"
                fi
            else
                [[ -n "$date_str" ]] && unparsed_dates=$((unparsed_dates + 1))
            fi
        fi
    done < <(echo "$claim_json" | jq -r '.sources // [] | map([.credibility // "unknown", .url // "", .date // (.as_of // "")])[] | @tsv')

    trust_score_float=$(printf "%0.4f" "$trust_score")
    total_trust_score=$(python3 - <<PY
from decimal import Decimal
print((Decimal("$total_trust_score") + Decimal("$trust_score_float")).quantize(Decimal("0.0001")))
PY
)
    trust_score_count=$((trust_score_count + 1))

    declare -a claim_failures=()

    if (( sources_count < MIN_SOURCES_PER_CLAIM )); then
        claim_failures+=("Insufficient sources: require at least $MIN_SOURCES_PER_CLAIM, found $sources_count")
    fi

    if (( unique_domains < MIN_INDEPENDENT_SOURCES )); then
        claim_failures+=("Not enough independent sources: require $MIN_INDEPENDENT_SOURCES unique domains, found $unique_domains")
    fi

    if (( $(echo "$trust_score_float < $MIN_TRUST_SCORE" | bc -l) )); then
        claim_failures+=("Trust score too low: require ≥ $MIN_TRUST_SCORE, score $trust_score_float")
    fi

    if (( $(echo "$confidence < $MIN_CLAIM_CONFIDENCE" | bc -l) )); then
        low_confidence_claims=$((low_confidence_claims + 1))
        claim_failures+=("Claim confidence below threshold: require ≥ $MIN_CLAIM_CONFIDENCE, got $confidence")
    fi

    if [[ "$RECENCY_ENFORCE" == "true" ]]; then
        if [[ "$parseable_dates" -eq 0 ]]; then
            if [[ "$ALLOW_UNPARSED_DATES" == "false" ]]; then
                claim_failures+=("No parsable source dates and recency enforcement requires valid dates")
            fi
        else
            if [[ -n "$newest_source_days" && "$newest_source_days" -gt "$MAX_SOURCE_AGE_DAYS" ]]; then
                claim_failures+=("Most recent source is ${newest_source_days} days old; maximum allowed is $MAX_SOURCE_AGE_DAYS days")
            fi
        fi
    fi

    if (( ${#claim_failures[@]} > 0 )); then
        failed_claims=$((failed_claims + 1))
    fi

    failures_json='[]'
    if (( ${#claim_failures[@]} > 0 )); then
        failures_json=$(printf '%s\n' "${claim_failures[@]}" | jq -R -s 'split("\n")[:-1]')
    fi

    jq -n \
        --arg id "$claim_id" \
        --arg statement "$statement" \
        --argjson sources_count "$sources_count" \
        --argjson unique_domains "$unique_domains" \
        --arg trust_score "$trust_score_float" \
        --arg confidence "$confidence" \
        --argjson failures "$failures_json" \
        --argjson parseable_dates "$parseable_dates" \
        --argjson unparsed_dates "$unparsed_dates" \
        --arg newest_days "${newest_source_days:-null}" \
        --arg oldest_days "${oldest_source_days:-null}" \
        '{
            id: $id,
            statement: $statement,
            sources: {
                count: $sources_count,
                independent_count: $unique_domains,
                trust_score: ($trust_score | tonumber)
            },
            confidence: ($confidence | tonumber),
            recency: {
                parseable_dates: $parseable_dates,
                unparsed_dates: $unparsed_dates,
                newest_source_age_days: (if $newest_days == "null" then null else ($newest_days | tonumber) end),
                oldest_source_age_days: (if $oldest_days == "null" then null else ($oldest_days | tonumber) end)
            },
            failures: $failures
        }' >>"$tmp_claims"
done < <(jq -c '.claims[]' "$KG_FILE")

# Session-level checks
unresolved_contradictions=$(jq '.stats.unresolved_contradictions // 0' "$KG_FILE")
overall_failures=0
if (( failed_claims > 0 )); then
    overall_failures=$((overall_failures + failed_claims))
fi

if (( low_confidence_claims > MAX_LOW_CONFIDENCE_CLAIMS )); then
    excess=$((low_confidence_claims - MAX_LOW_CONFIDENCE_CLAIMS))
    jq -n \
        --arg check "Low confidence claims" \
        --arg result "failed" \
        --arg detail "Too many low-confidence claims: allow $MAX_LOW_CONFIDENCE_CLAIMS, have $low_confidence_claims (excess $excess)" \
        '{check: $check, result: $result, detail: $detail}' >>"$tmp_session"
    overall_failures=$((overall_failures + 1))
else
    jq -n \
        --arg check "Low confidence claims" \
        --arg result "passed" \
        --arg detail "Low-confidence claims within threshold" \
        '{check: $check, result: $result, detail: $detail}' >>"$tmp_session"
fi

if (( unresolved_contradictions > MAX_UNRESOLVED_CONTRADICTIONS )); then
    jq -n \
        --arg check "Unresolved contradictions" \
        --arg result "failed" \
        --arg detail "Found $unresolved_contradictions unresolved contradictions (limit $MAX_UNRESOLVED_CONTRADICTIONS)" \
        '{check: $check, result: $result, detail: $detail}' >>"$tmp_session"
    overall_failures=$((overall_failures + 1))
else
    jq -n \
        --arg check "Unresolved contradictions" \
        --arg result "passed" \
        --arg detail "Contradictions within threshold" \
        '{check: $check, result: $result, detail: $detail}' >>"$tmp_session"
fi

claim_results=$(if [[ -s "$tmp_claims" ]]; then jq -s '.' "$tmp_claims"; else echo '[]'; fi)
session_checks=$(if [[ -s "$tmp_session" ]]; then jq -s '.' "$tmp_session"; else echo '[]'; fi)

average_trust=$(python3 - <<PY
from decimal import Decimal
count = Decimal("$trust_score_count")
if count == 0:
    print("0")
else:
    total = Decimal("$total_trust_score")
    print((total / count).quantize(Decimal("0.0001")))
PY
)

status="passed"
if (( failed_claims > 0 || overall_failures > 0 )); then
    status="failed"
fi

summary_json=$(jq -n \
    --arg status "$status" \
    --arg evaluated_at "$(get_timestamp)" \
    --argjson total_claims "$total_claims" \
    --argjson failed_claims "$failed_claims" \
    --argjson low_confidence "$low_confidence_claims" \
    --arg average_trust "$average_trust" \
    --argjson contradictions "$unresolved_contradictions" \
    --arg mode "$MODE" \
    --argjson thresholds "$(echo "$CONFIG_JSON" | jq '.thresholds')" \
    --argjson recency "$(echo "$CONFIG_JSON" | jq '.recency')" \
    --argjson trust_weights "$(echo "$CONFIG_JSON" | jq '.trust_weights')" \
    --argjson claim_results "$claim_results" \
    --argjson session_checks "$session_checks" \
    '
        def suggestion($text):
            if $text | test("Insufficient sources") then "Add more cited evidence so the claim meets the minimum source count."
            elif $text | test("Not enough independent sources") then "Source the claim from additional, independent domains."
            elif $text | test("Trust score too low") then "Replace or supplement with higher-trust sources (peer-reviewed, official, or academic)."
            elif $text | test("Most recent source is") then "Locate more recent evidence that falls within the recency window."
            elif $text | test("Claim confidence below threshold") then "Gather additional evidence to raise the claim confidence before publishing."
            elif $text | test("No parsable source dates") then "Ensure each source has a clear, machine-readable publication date."
            else empty end;
        {
            status: $status,
            mode: $mode,
            evaluated_at: $evaluated_at,
            summary: {
                total_claims: $total_claims,
                failed_claims: $failed_claims,
                low_confidence_claims: $low_confidence,
                unresolved_contradictions: $contradictions,
                average_trust_score: ($average_trust | tonumber),
                thresholds: $thresholds,
                recency: $recency
            },
            trusts: $trust_weights,
            claim_results: $claim_results,
            session_checks: $session_checks,
            recommendations: (
                [$claim_results[]? | (.failures[]? | suggestion(.))] | map(select(. != "")) | unique
            )
        }
    '
)

summary_compact=$(echo "$summary_json" | jq '{
        status,
        mode,
        summary,
        recommendations,
        totals: {
            total_claims: .summary.total_claims,
            failed_claims: .summary.failed_claims
        }
    }')

echo "$summary_json" >"$OUTPUT_PATH"
echo "$summary_compact" >"$SUMMARY_PATH"

if [[ "$status" == "passed" ]]; then
    echo "✓ Quality gate passed (${total_claims} claims evaluated)" >&2
    exit 0
fi

echo "✗ Quality gate flagged ${failed_claims} claims" >&2
echo "  See $OUTPUT_FILENAME for details" >&2

if [[ "$MODE" == "advisory" ]]; then
    exit 0
fi

exit 2
