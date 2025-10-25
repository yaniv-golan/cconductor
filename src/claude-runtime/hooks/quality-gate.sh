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
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/json-helpers.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/domain-helpers.sh" 2>/dev/null || true

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

KG_FILE="$SESSION_DIR/knowledge/knowledge-graph.json"
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

# Recency settings
RECENCY_ENFORCE=$(echo "$CONFIG_JSON" | jq -r '.recency.enforce // false')
MAX_SOURCE_AGE_DAYS=$(echo "$CONFIG_JSON" | jq -r '.recency.max_source_age_days // 0')
ALLOW_UNPARSED_DATES=$(echo "$CONFIG_JSON" | jq -r '.recency.allow_unparsed_dates // true')

# Trust weights
TRUST_WEIGHTS_LIST=$(echo "$CONFIG_JSON" | jq -r '.trust_weights // {} | to_entries[] | "\(.key)\t\(.value)"')
DEFAULT_TRUST_WEIGHT=$(echo "$CONFIG_JSON" | jq -r '.default_trust_weight // 0')

HEURISTICS_FILE="$SESSION_DIR/meta/domain-heuristics.json"
DOMAIN_HEURISTICS_JSON=""
if [[ -f "$HEURISTICS_FILE" ]]; then
    DOMAIN_HEURISTICS_JSON=$(cat "$HEURISTICS_FILE" 2>/dev/null || echo "")
fi

DOMAIN_AWARE=$(echo "$CONFIG_JSON" | jq -r '.domain_aware // false' | tr '[:upper:]' '[:lower:]')
FALLBACK_TO_GLOBAL=$(echo "$CONFIG_JSON" | jq -r '.fallback_to_global_thresholds // true' | tr '[:upper:]' '[:lower:]')
UNCAT_WARN_ENABLED=$(echo "$CONFIG_JSON" | jq -r '.uncategorized_source_warnings.enabled // false' | tr '[:upper:]' '[:lower:]')
UNCAT_WARN_THRESHOLD=$(echo "$CONFIG_JSON" | jq -r '.uncategorized_source_warnings.threshold_percentage // 15')
UNCAT_WARN_INCLUDE=$(echo "$CONFIG_JSON" | jq -r '.uncategorized_source_warnings.include_in_summary // true' | tr '[:upper:]' '[:lower:]')

declare -A DOMAIN_TOPIC_LIMITS=()
DOMAIN_RECENCY_FALLBACK=""
DOMAIN_TOTAL_SOURCES=0
DOMAIN_UNCATEGORIZED_COUNT=0
DOMAIN_UNCATEGORIZED_PCT="0"
DOMAIN_UNCATEGORIZED_SAMPLES_JSON='[]'
DOMAIN_UNCATEGORIZED_ALERT=false

if [[ -n "$DOMAIN_HEURISTICS_JSON" ]]; then
    while IFS=$'\t' read -r topic limit; do
        [[ -z "$topic" ]] && continue
        [[ -z "$limit" || "$limit" == "null" ]] && continue
        DOMAIN_TOPIC_LIMITS["$topic"]="$limit"
    done < <(echo "$DOMAIN_HEURISTICS_JSON" | jq -r '.freshness_requirements[]? | "\(.topic)\t\(.max_age_days // 0)"' 2>/dev/null || echo "")

    if [[ ${#DOMAIN_TOPIC_LIMITS[@]} -gt 0 ]]; then
        max_limit=0
        for limit in "${DOMAIN_TOPIC_LIMITS[@]}"; do
            [[ -z "$limit" ]] && continue
            if [[ "$limit" =~ ^[0-9]+$ ]] && (( limit > max_limit )); then
                max_limit=$limit
            fi
        done
        if (( max_limit > 0 )); then
            DOMAIN_RECENCY_FALLBACK="$max_limit"
        fi
    fi
fi

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

tmp_claims="$(mktemp)"
tmp_session="$(mktemp)"
trap 'rm -f "$tmp_claims" "$tmp_session"' EXIT

check_stakeholder_balance() {
    local session_dir="$1"

    if [[ "$DOMAIN_AWARE" != "true" ]] || [[ -z "$DOMAIN_HEURISTICS_JSON" ]]; then
        return 0
    fi
    if ! command -v map_source_to_stakeholder >/dev/null 2>&1; then
        return 0
    fi

    local kg_file="$session_dir/knowledge/knowledge-graph.json"
    if [[ ! -f "$kg_file" ]]; then
        return 0
    fi

    declare -A stakeholder_counts=()
    while IFS= read -r category; do
        [[ -z "$category" ]] && continue
        stakeholder_counts["$category"]=0
    done < <(echo "$DOMAIN_HEURISTICS_JSON" | jq -r '.stakeholder_categories | keys[]?' 2>/dev/null || echo "")

    local sample_limit=5
    local -a uncategorized_samples=()
    DOMAIN_TOTAL_SOURCES=0
    DOMAIN_UNCATEGORIZED_COUNT=0

    while IFS= read -r source_json; do
        [[ -z "$source_json" || "$source_json" == "null" ]] && continue
        DOMAIN_TOTAL_SOURCES=$((DOMAIN_TOTAL_SOURCES + 1))
        local category
        category=$(map_source_to_stakeholder "$source_json" "$DOMAIN_HEURISTICS_JSON")
        if [[ -n "$category" && "$category" != "uncategorized" ]]; then
            if [[ -z "${stakeholder_counts[$category]+_}" ]]; then
                stakeholder_counts["$category"]=0
            fi
            stakeholder_counts["$category"]=$((stakeholder_counts["$category"] + 1))
        else
            DOMAIN_UNCATEGORIZED_COUNT=$((DOMAIN_UNCATEGORIZED_COUNT + 1))
            if ((${#uncategorized_samples[@]} < sample_limit)); then
                local url title sample
                url=$(echo "$source_json" | jq -r '.url // ""')
                title=$(echo "$source_json" | jq -r '.title // ""')
                sample=$(jq -n --arg url "$url" --arg title "$title" '{url:$url,title:$title}')
                uncategorized_samples+=("$sample")
            fi
        fi
    done < <(jq -c '.claims[]? | .sources[]?' "$kg_file" 2>/dev/null || echo "")

    if ((${#uncategorized_samples[@]} > 0)); then
        DOMAIN_UNCATEGORIZED_SAMPLES_JSON=$(printf '%s\n' "${uncategorized_samples[@]}" | jq -s '.' 2>/dev/null || echo '[]')
    else
        DOMAIN_UNCATEGORIZED_SAMPLES_JSON='[]'
    fi

    if [[ $DOMAIN_TOTAL_SOURCES -gt 0 ]]; then
        DOMAIN_UNCATEGORIZED_PCT=$(awk "BEGIN {printf \"%.1f\", ($DOMAIN_UNCATEGORIZED_COUNT / $DOMAIN_TOTAL_SOURCES) * 100}")
    else
        DOMAIN_UNCATEGORIZED_PCT="0"
    fi

    DOMAIN_UNCATEGORIZED_ALERT=false
    if [[ "$UNCAT_WARN_ENABLED" == "true" && $DOMAIN_TOTAL_SOURCES -gt 0 ]]; then
        if awk "BEGIN {exit !($DOMAIN_UNCATEGORIZED_PCT > $UNCAT_WARN_THRESHOLD)}"; then
            DOMAIN_UNCATEGORIZED_ALERT=true
        fi
    fi

    local missing_critical=()
    while IFS=$'\t' read -r category importance; do
        [[ -z "$category" ]] && continue
        if [[ "$importance" == "critical" ]]; then
            if [[ ${stakeholder_counts[$category]:-0} -eq 0 ]]; then
                missing_critical+=("$category")
            fi
        fi
    done < <(echo "$DOMAIN_HEURISTICS_JSON" | jq -r '.stakeholder_categories | to_entries[]? | "\(.key)\t\(.value.importance)"' 2>/dev/null || echo "")

    if [[ ${#missing_critical[@]} -gt 0 ]]; then
        local missing_list
        missing_list=$(printf '%s, ' "${missing_critical[@]}" | sed 's/, $//')
        jq -n \
            --arg check "Stakeholder balance" \
            --arg result "failed" \
            --arg detail "Missing critical stakeholder perspectives: $missing_list" \
            '{check: $check, result: $result, detail: $detail}' >>"$tmp_session"
        return 1
    fi

    jq -n \
        --arg check "Stakeholder balance" \
        --arg result "passed" \
        --arg detail "All critical stakeholder categories represented" \
        '{check: $check, result: $result, detail: $detail}' >>"$tmp_session"
    return 0
}

check_mandatory_milestones() {
    local session_dir="$1"

    if [[ "$DOMAIN_AWARE" != "true" ]] || [[ -z "$DOMAIN_HEURISTICS_JSON" ]]; then
        return 0
    fi
    if ! command -v match_watch_item >/dev/null 2>&1; then
        return 0
    fi

    local kg_file="$session_dir/knowledge/knowledge-graph.json"
    if [[ ! -f "$kg_file" ]]; then
        return 0
    fi

    local missing_critical=()

    while IFS= read -r watch_item_json; do
        [[ -z "$watch_item_json" || "$watch_item_json" == "null" ]] && continue
        local importance
        importance=$(echo "$watch_item_json" | jq -r '.importance // ""')
        if [[ "$importance" != "critical" ]]; then
            continue
        fi
        local found=false
        while IFS= read -r claim_json; do
            [[ -z "$claim_json" || "$claim_json" == "null" ]] && continue
            if match_watch_item "$watch_item_json" "$claim_json"; then
                found=true
                break
            fi
        done < <(jq -c '.claims[]?' "$kg_file" 2>/dev/null || echo "")
        if [[ "$found" == false ]]; then
            local canonical
            canonical=$(echo "$watch_item_json" | jq -r '.canonical // ""')
            [[ -n "$canonical" ]] && missing_critical+=("$canonical")
        fi
    done < <(echo "$DOMAIN_HEURISTICS_JSON" | jq -c '.mandatory_watch_items[]?' 2>/dev/null || echo "")

    if [[ ${#missing_critical[@]} -gt 0 ]]; then
        local missing_list
        missing_list=$(printf '%s, ' "${missing_critical[@]}" | sed 's/, $//')
        jq -n \
            --arg check "Mandatory milestones" \
            --arg result "failed" \
            --arg detail "Critical watch items not researched: $missing_list" \
            '{check: $check, result: $result, detail: $detail}' >>"$tmp_session"
        return 1
    fi

    jq -n \
        --arg check "Mandatory milestones" \
        --arg result "passed" \
        --arg detail "All critical watch items addressed" \
        '{check: $check, result: $result, detail: $detail}' >>"$tmp_session"
    return 0
}

apply_domain_recency() {
    local session_dir="$1"

    if [[ "$DOMAIN_AWARE" != "true" ]] || [[ -z "$DOMAIN_HEURISTICS_JSON" ]]; then
        return 0
    fi
    if [[ -z "$claim_results" || "$claim_results" == "null" ]]; then
        return 0
    fi

    local violations
    violations=$(echo "$claim_results" | jq -c '[.[] | select(.confidence_surface.domain_recency.max_age_days != null and .confidence_surface.newest_source_age_days != null and (.confidence_surface.newest_source_age_days > (.confidence_surface.domain_recency.max_age_days | tonumber))) | {id, topic: (.confidence_surface.domain_recency.topic // null), newest: .confidence_surface.newest_source_age_days, max_allowed: (.confidence_surface.domain_recency.max_age_days | tonumber)}]')
    local violation_count
    violation_count=$(echo "$violations" | jq 'length')

    if (( violation_count > 0 )); then
        local detail
        detail=$(echo "$violations" | jq -r '[.[] | (.id + " (topic: " + (.topic // "unspecified") + ", newest: " + ((.newest | tostring) + "d > max: " + (.max_allowed | tostring) + "d)"))] | join("; ")')
        jq -n \
            --arg check "Domain recency" \
            --arg result "failed" \
            --arg detail "$detail" \
            '{check: $check, result: $result, detail: $detail}' >>"$tmp_session"
        return 1
    fi

    jq -n \
        --arg check "Domain recency" \
        --arg result "passed" \
        --arg detail "All evaluated claims meet topic-specific recency windows" \
        '{check: $check, result: $result, detail: $detail}' >>"$tmp_session"
    return 0
}

total_claims=$(jq '.claims | length' "$KG_FILE")
failed_claims=0
low_confidence_claims=0
total_trust_score=0
trust_score_count=0

date_age_map="{}"
if [[ "$RECENCY_ENFORCE" == "true" ]]; then
    all_dates_json=$(jq -c '[.claims[] | (.sources // [])[]? | (.date // (.as_of // "")) | select(. != null and . != "")] | unique' "$KG_FILE")
    
    # Trim whitespace to catch whitespace-only strings
    trimmed=$(printf '%s' "$all_dates_json" | tr -d '[:space:]')
    
    if [[ -n "$trimmed" && "$trimmed" != "[]" ]]; then
        # Redirect Python stderr to suppress JSONDecodeError tracebacks
        date_age_map=$(python3 2>/dev/null <<PY || echo ""
import json
from datetime import datetime, timezone
import sys

dates = json.loads('''$all_dates_json''')
formats = [
    "%Y-%m-%d",
    "%Y/%m/%d",
    "%Y-%m",
    "%Y/%m",
    "%Y",
    "%b %d %Y",
    "%b %Y",
    "%B %d %Y",
    "%B %Y",
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

result = {}
for raw in dates:
    raw_str = raw.strip()
    if not raw_str:
        continue
    parsed = iso_parse(raw_str)
    if parsed is None:
        for fmt in formats:
            try:
                dt = datetime.strptime(raw_str, fmt)
            except ValueError:
                continue
            parsed = dt.date() if hasattr(dt, "date") else dt
            break
    if parsed is None:
        continue
    if raw_str.isdigit() and len(raw_str) == 4:
        parsed = parsed.replace(month=7, day=1)
    result[raw] = (now - parsed).days

print(json.dumps(result))
PY
)
        if [[ -z "$date_age_map" || "$date_age_map" == "" ]]; then
            log_warn "quality-gate: recency parser failed, disabling recency checks"
            date_age_map="{}"
        fi
    fi
fi

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

    claim_topic=$(echo "$claim_json" | jq -r '.topic // ""')
    [[ "$claim_topic" == "null" ]] && claim_topic=""
    if [[ -z "$claim_topic" && "$DOMAIN_AWARE" == "true" && -n "$DOMAIN_HEURISTICS_JSON" ]]; then
        if command -v infer_claim_topic >/dev/null 2>&1; then
            inferred_topic=$(infer_claim_topic "$statement" "$DOMAIN_HEURISTICS_JSON")
            if [[ -n "$inferred_topic" && "$inferred_topic" != "unclassified" ]]; then
                claim_topic="$inferred_topic"
            fi
        fi
    fi

    effective_recency_limit="$MAX_SOURCE_AGE_DAYS"
    if [[ "$DOMAIN_AWARE" == "true" && -n "$DOMAIN_HEURISTICS_JSON" ]]; then
        effective_recency_limit=""
        if [[ -n "$claim_topic" && -n "${DOMAIN_TOPIC_LIMITS[$claim_topic]:-}" ]]; then
            effective_recency_limit="${DOMAIN_TOPIC_LIMITS[$claim_topic]}"
        elif [[ -n "$DOMAIN_RECENCY_FALLBACK" ]]; then
            effective_recency_limit="$DOMAIN_RECENCY_FALLBACK"
        elif [[ "$FALLBACK_TO_GLOBAL" == "true" ]]; then
            effective_recency_limit="$MAX_SOURCE_AGE_DAYS"
        fi
    fi

    domain_topic_arg=""
    domain_recency_limit_arg="null"
    if [[ "$DOMAIN_AWARE" == "true" && -n "$DOMAIN_HEURISTICS_JSON" ]]; then
        domain_topic_arg="$claim_topic"
        if [[ -n "$effective_recency_limit" ]]; then
            domain_recency_limit_arg="$effective_recency_limit"
        fi
    fi

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

        if [[ "$RECENCY_ENFORCE" == "true" && -n "$date_str" ]]; then
            age=$(echo "$date_age_map" | jq -r --arg key "$date_str" '.[ $key ] // empty')
            if [[ -n "$age" && "$age" != "null" ]]; then
                parseable_dates=$((parseable_dates + 1))
                if [[ -z "$oldest_source_days" || "$age" -gt "$oldest_source_days" ]]; then
                    oldest_source_days="$age"
                fi
                if [[ -z "$newest_source_days" || "$age" -lt "$newest_source_days" ]]; then
                    newest_source_days="$age"
                fi
            else
                unparsed_dates=$((unparsed_dates + 1))
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
            recency_limit="$effective_recency_limit"
            if [[ -z "$recency_limit" && ! ( "$DOMAIN_AWARE" == "true" && -n "$DOMAIN_HEURISTICS_JSON" ) ]]; then
                recency_limit="$MAX_SOURCE_AGE_DAYS"
            fi
            if [[ -n "$recency_limit" && -n "$newest_source_days" ]] && [[ "$newest_source_days" -gt "$recency_limit" ]]; then
                recency_detail="Most recent source is ${newest_source_days} days old; maximum allowed is $recency_limit days"
                if [[ -n "$claim_topic" ]]; then
                    recency_detail+=" for topic '$claim_topic'"
                fi
                claim_failures+=("$recency_detail")
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
        --arg domain_topic "$domain_topic_arg" \
        --argjson domain_recency_limit "$domain_recency_limit_arg" \
        --arg newest_days "${newest_source_days:-null}" \
        --arg oldest_days "${oldest_source_days:-null}" \
        --arg evaluated_at "$(get_timestamp)" \
        '{
            id: $id,
            statement: $statement,
            agent_confidence: ($confidence | tonumber),
            confidence_surface: {
                source_count: $sources_count,
                independent_source_count: $unique_domains,
                trust_score: ($trust_score | tonumber),
                newest_source_age_days: (if $newest_days == "null" then null else ($newest_days | tonumber) end),
                oldest_source_age_days: (if $oldest_days == "null" then null else ($oldest_days | tonumber) end),
                parseable_dates: $parseable_dates,
                unparsed_dates: $unparsed_dates,
                domain_recency: {
                    topic: (if $domain_topic == "" then null else $domain_topic end),
                    max_age_days: (if $domain_recency_limit == null then null else $domain_recency_limit end)
                },
                limitation_flags: $failures,
                last_reviewed_at: $evaluated_at,
                status: (if ($failures | length) > 0 then "flagged" else "passed" end)
            }
        }' >>"$tmp_claims"
done < <(jq -c '.claims[]' "$KG_FILE")

# Session-level checks
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

# Contradiction detection removed - handled by fact-checker agent when orchestrator identifies conflicts

# Slurp temp files into arrays with fallback
claim_results=$(json_slurp_array "$tmp_claims" '[]')

if [[ "$DOMAIN_AWARE" == "true" && -n "$DOMAIN_HEURISTICS_JSON" ]]; then
    check_stakeholder_balance "$SESSION_DIR" || true
    check_mandatory_milestones "$SESSION_DIR" || true
    apply_domain_recency "$SESSION_DIR" || true
fi

session_checks=$(json_slurp_array "$tmp_session" '[]')

# Double-check for empty strings (defensive)
if [[ -z "$claim_results" || "$claim_results" == "null" ]]; then
    log_warn "quality-gate: claim_results empty after slurp, using fallback"
    claim_results='[]'
fi

if [[ -z "$session_checks" || "$session_checks" == "null" ]]; then
    log_warn "quality-gate: session_checks empty after slurp, using fallback"
    session_checks='[]'
fi

thresholds_json=$(echo "$CONFIG_JSON" | jq '.thresholds // {}')
recency_json=$(echo "$CONFIG_JSON" | jq '.recency // {}')
trust_weights_json=$(echo "$CONFIG_JSON" | jq '.trust_weights // {}')

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

uncategorized_summary='{"count":0,"total":0,"percentage":0,"samples":[],"action_required":null}'
if [[ "$DOMAIN_AWARE" == "true" && -n "$DOMAIN_HEURISTICS_JSON" && "$UNCAT_WARN_INCLUDE" == "true" ]]; then
    samples_json="$DOMAIN_UNCATEGORIZED_SAMPLES_JSON"
    threshold_flag="false"
    [[ "$DOMAIN_UNCATEGORIZED_ALERT" == "true" ]] && threshold_flag="true"
    action_msg="Review uncategorized sources. Add patterns to ~/.config/cconductor/stakeholder-patterns.json if they represent important stakeholders."
    uncategorized_summary=$(jq -n \
        --argjson count "${DOMAIN_UNCATEGORIZED_COUNT:-0}" \
        --argjson total "${DOMAIN_TOTAL_SOURCES:-0}" \
        --arg pct "${DOMAIN_UNCATEGORIZED_PCT:-0}" \
        --argjson samples "$samples_json" \
        --arg action "$action_msg" \
        --argjson alert "$threshold_flag" \
        '{
            count: $count,
            total: $total,
            percentage: ($pct | tonumber),
            samples: $samples,
            action_required: (if ($alert == true and $count > 0) then $action else null end)
        }')
fi

summary_json=$(jq -n \
    --arg status "$status" \
    --arg evaluated_at "$(get_timestamp)" \
    --argjson total_claims "$total_claims" \
    --argjson failed_claims "$failed_claims" \
    --argjson low_confidence "$low_confidence_claims" \
    --arg average_trust "$average_trust" \
    --arg mode "$MODE" \
    --argjson thresholds "$thresholds_json" \
    --argjson recency "$recency_json" \
    --argjson trust_weights "$trust_weights_json" \
    --argjson claim_results "$claim_results" \
    --argjson session_checks "$session_checks" \
    --argjson uncategorized "$uncategorized_summary" \
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
                average_trust_score: ($average_trust | tonumber),
                thresholds: $thresholds,
                recency: $recency
            },
            trusts: $trust_weights,
            claim_results: $claim_results,
            session_checks: $session_checks,
            uncategorized_sources: $uncategorized,
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
        uncategorized_sources,
        totals: {
            total_claims: .summary.total_claims,
            failed_claims: .summary.failed_claims
        }
    }')

# Atomic writes to prevent race conditions with readers
# Write to temp files first, then atomically move into place
echo "$summary_json" >"${OUTPUT_PATH}.tmp.$$"
mv "${OUTPUT_PATH}.tmp.$$" "$OUTPUT_PATH"

echo "$summary_compact" >"${SUMMARY_PATH}.tmp.$$"
mv "${SUMMARY_PATH}.tmp.$$" "$SUMMARY_PATH"

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
