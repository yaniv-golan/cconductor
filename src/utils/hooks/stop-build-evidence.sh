#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source core helpers with fallback (hooks must never fail)
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/core-helpers.sh" 2>/dev/null || {
    # Minimal fallbacks if core-helpers unavailable
    get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%S.%6NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ"; }
}

if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
    echo "stop-build-evidence.sh requires Bash 4.0 or newer." >&2
    exit 1
fi

declare -A SUPPORTED_MODE_MAP=([disabled]=1 [collect]=1 [render]=1)

single_line() {
    local text="$1"
    printf '%s' "$text" | tr '\n' ' ' | tr -s '[:space:]' ' ' | sed -e 's/^ *//' -e 's/ *$//'
}

get_mode() {
    local mode
    mode=$(printf '%s' "${CCONDUCTOR_EVIDENCE_MODE:-disabled}" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    if [[ -z "$mode" || -z "${SUPPORTED_MODE_MAP[$mode]:-}" ]]; then
        mode="disabled"
    fi
    printf '%s' "$mode"
}

read_payload() {
    if [[ -t 0 ]]; then
        printf '{}'
        return
    fi
    local data
    data=$(cat)
    if [[ -z "$data" ]]; then
        printf '{}'
    else
        printf '%s' "$data"
    fi
}

normalize_source_url() {
    local raw="$1"
    local session_dir="$2"
    if [[ -z "$raw" || "$raw" == "null" ]]; then
        printf '\t'
        return
    fi
    if [[ "$raw" =~ ^https?:// ]]; then
        printf '%s\tweb' "$raw"
        return
    fi
    local candidate="$raw"
    if [[ "$candidate" != /* ]]; then
        candidate="$session_dir/$candidate"
    fi
    if [[ ! -e "$candidate" ]]; then
        printf '\t'
        return
    fi
    local abs_path
    abs_path=$(cd "$(dirname "$candidate")" 2>/dev/null && pwd)
    abs_path="${abs_path}/$(basename "$candidate")"
    local rel="$abs_path"
    case "$abs_path" in
        "$session_dir"*)
            rel="${abs_path#"$session_dir"/}"
            ;;
    esac
    printf '%s\tlocal' "$rel"
}

build_text_fragment() {
    local url="$1"
    local snippet="${2-}"
    local context="${3-}"

    if [[ -z "$snippet" || -z "$url" ]]; then
        printf '%s' "$url"
        return
    fi
    if [[ ! "$url" =~ ^https?:// ]]; then
        printf '%s' "$url"
        return
    fi
    if [[ "$url" =~ \.pdf($|[?#]) ]]; then
        printf '%s' "$url"
        return
    fi
    if [[ ! -f "$SCRIPT_DIR/evidence_fragment.pl" ]] || ! command -v perl >/dev/null 2>&1; then
        printf '%s' "$url"
        return
    fi

    local payload
    payload=$(jq -n --arg snippet "$snippet" --arg context "$context" '{snippet: $snippet, context: $context}')
    local result
    result=$(printf '%s' "$payload" | perl "$SCRIPT_DIR/evidence_fragment.pl" "$url" 2>/dev/null || true)
    result=${result//$'\r'/}
    result=${result//$'\n'/}
    if [[ -n "$result" ]]; then
        printf '%s' "$result"
    else
        printf '%s' "$url"
    fi
}

compute_location_metadata() {
    local body_path="$1"
    local snippet="$2"
    if [[ -z "$snippet" || -z "$body_path" || ! -f "$body_path" ]]; then
        printf '{}'
        return
    fi
    SNIPPET="$snippet" perl -0 -MJSON::PP -e '
        use strict; use warnings;
        my ($path) = @ARGV;
        my $snippet = $ENV{SNIPPET} // "";
        open my $fh, "<:encoding(UTF-8)", $path or exit 0;
        local $/;
        my $text = <$fh> // "";
        close $fh;
        my ($start, $end, $para_idx);
        if (length $snippet) {
            my $pos = index($text, $snippet);
            my $search_text = $text;
            my $search_snippet = $snippet;
            if ($pos < 0) {
                my $norm_text = $text;
                $norm_text =~ s/\s+/ /g;
                my $norm_snippet = $snippet;
                $norm_snippet =~ s/\s+/ /g;
                $pos = index($norm_text, $norm_snippet);
                if ($pos >= 0) {
                    $search_text = $norm_text;
                    $search_snippet = $norm_snippet;
                }
            }
            if ($pos >= 0) {
                $start = $pos;
                $end = $pos + length($search_snippet);
                my @paragraphs = split(/\n\s*\n/, $search_text);
                my $cursor = 0;
                for my $i (0 .. $#paragraphs) {
                    my $p = $paragraphs[$i];
                    my $found = index($search_text, $p, $cursor);
                    next if $found < 0;
                    my $finish = $found + length($p);
                    $cursor = $finish;
                    if ($found <= $start && $start < $finish) {
                        $para_idx = $i;
                        last;
                    }
                }
            }
        }
        my %out;
        $out{paragraph_index} = $para_idx if defined $para_idx;
        if (defined $start) {
            $out{char_span} = [$start, $end];
        }
        print JSON::PP->new->canonical->encode(\%out);
    ' "$body_path"
}

lookup_manifest_entry() {
    local manifest_json="$1"
    local key="$2"
    local kind="$3"
    if [[ -z "$manifest_json" ]]; then
        printf '{}'
        return
    fi
    local filter
    if [[ "$kind" == "web" ]]; then
        # shellcheck disable=SC2016
        filter='(.entries // []) | map(select(.url == $key)) | first // {}'
    else
        # shellcheck disable=SC2016
        filter='(.entries // []) | map(select(.url == $key or .local_path == $key)) | first // {}'
    fi
    jq -c --arg key "$key" "$filter" <<<"$manifest_json"
}

append_source_json() {
    local sources_file="$1"
    local id="$2"
    local url="$3"
    local title="$4"
    local quote="$5"
    local deep_link="$6"
    local retrieved_at="$7"
    local paragraph_json="$8"
    jq -n \
        --arg id "$id" \
        --arg url "$url" \
        --arg title "$title" \
        --arg quote "$quote" \
        --arg deep_link "$deep_link" \
        --arg retrieved_at "$retrieved_at" \
        --argjson meta "$paragraph_json" '
        {
          id: $id,
          url: ($url | select(length>0)),
          title: ($title | select(length>0)),
          quote: ($quote | select(length>0)),
          deep_link: ($deep_link | select(length>0)),
          retrieved_at: ($retrieved_at | select(length>0))
        }
        | (if ($meta.paragraph_index? != null) then .paragraph_index = $meta.paragraph_index else . end)
        | (if ($meta.char_span? != null) then .char_span = $meta.char_span else . end)
        | with_entries(select(.value != null))
    ' >> "$sources_file"
}

collect_array() {
    local file="$1"
    if [[ ! -s "$file" ]]; then
        printf '[]'
        return
    fi
    jq -s 'map(.)' "$file"
}

build_evidence_from_findings() {
    local session_dir="$1"
    local manifest_path="$session_dir/cache/webfetch/index.json"
    local manifest_json="{}"
    if [[ -f "$manifest_path" ]]; then
        manifest_json=$(cat "$manifest_path")
    fi

    local sources_file claims_file
    sources_file=$(mktemp)
    claims_file=$(mktemp)

    declare -A source_map=()
    local source_count=0
    local claim_count=0

    shopt -s nullglob
    for finding_file in "$session_dir"/raw/findings-*.json; do
        while IFS= read -r claim_json; do
            local statement
            statement=$(jq -r '.statement // ""' <<<"$claim_json")
            [[ -z "$statement" || "$statement" == "null" ]] && continue
            local why_supported
            why_supported=$(jq -r '.why_supported // "Source excerpt supports the claim."' <<<"$claim_json")
            local confidence
            confidence=$(jq -r '.confidence // empty' <<<"$claim_json")

            mapfile -t source_objs < <(jq -c '.sources[]?' <<<"$claim_json")
            local claim_sources=()
            local source_item
            for source_item in "${source_objs[@]}"; do
                local raw_url
                raw_url=$(jq -r '.url // ""' <<<"$source_item")
                local title
                title=$(jq -r '.title // ""' <<<"$source_item")
                local quote_text
                quote_text=$(jq -r '.relevant_quote // .quote // ""' <<<"$source_item")
                read -r normalized kind <<<"$(normalize_source_url "$raw_url" "$session_dir")"
                if [[ -z "$normalized" ]]; then
                    continue
                fi
                local manifest_key="$raw_url"
                if [[ "$kind" == "web" ]]; then
                    manifest_key="$normalized"
                fi
                local manifest_entry
                manifest_entry=$(lookup_manifest_entry "$manifest_json" "$manifest_key" "$kind")
                local body_file
                body_file=$(jq -r '.body_file // ""' <<<"$manifest_entry")
                local body_path=""
                if [[ -n "$body_file" ]]; then
                    body_path="$session_dir/cache/webfetch/$body_file"
                fi
                local location_meta
                location_meta=$(compute_location_metadata "$body_path" "$quote_text")
                [[ -z "$location_meta" ]] && location_meta='{}'
                local retrieved_at
                retrieved_at=$(jq -r '.date // .retrieved_at // empty' <<<"$source_item")
                if [[ -z "$retrieved_at" ]]; then
                    retrieved_at=$(jq -r '.fetched_at // empty' <<<"$manifest_entry")
                fi
                local deep_link
                deep_link=$(build_text_fragment "$normalized" "$quote_text" "${body_text:-}")
                local key="${normalized}||${title}||${quote_text}"
                local source_id
                if [[ -n "${source_map[$key]:-}" ]]; then
                    source_id="${source_map[$key]}"
                else
                    source_count=$((source_count + 1))
                    source_id="source_${source_count}"
                    source_map["$key"]="$source_id"
                    append_source_json "$sources_file" "$source_id" "$normalized" "$title" "$quote_text" "$deep_link" "$retrieved_at" "$location_meta"
                fi
                claim_sources+=("$source_id")
            done

            if [[ ${#claim_sources[@]} -eq 0 ]]; then
                continue
            fi

            claim_count=$((claim_count + 1))
            local marker="$claim_count"
            local claim_sources_json
            claim_sources_json=$(printf '%s\n' "${claim_sources[@]}" | jq -R 'select(length>0)' | jq -s 'map(.)')
            jq -n \
                --arg id "claim_${claim_count}" \
                --arg marker "$marker" \
                --arg statement "$statement" \
                --arg why "$why_supported" \
                --arg confidence "$confidence" \
                --argjson sources "$claim_sources_json" \
                --arg drop_null_confidence "true" '
                {
                  id: $id,
                  marker: $marker,
                  claim_text: ($statement | select(length>0)),
                  why_supported: ($why | select(length>0)),
                  sources: $sources
                }
                | with_entries(select(.value != null))
                | .confidence = (if $confidence == "" or $confidence == "null" then null else ($confidence | tonumber? // $confidence) end)
                | if ($drop_null_confidence == "true" and .confidence == null) then del(.confidence) else . end
            ' >> "$claims_file"
        done < <(jq -c '.claims[]?' "$finding_file")
    done
    shopt -u nullglob

    local claims_array
    claims_array=$(collect_array "$claims_file")
    local sources_array
    sources_array=$(collect_array "$sources_file")

    rm -f "$claims_file" "$sources_file"

    jq -n --argjson claims "$claims_array" --argjson sources "$sources_array" '{claims: $claims, sources: $sources}'
}

find_latest_assistant_message() {
    local transcript_path="$1"
    jq -s '
        [ .[]
          | select((.message.role == "assistant") and (((.message.content // []) | length) > 0))
          | select(any(.message.content[]?; (((.citations // []) | length) > 0)))
        ]
        | reverse
        | (.[0].message // {})
    ' "$transcript_path"
}

parse_block_entries() {
    local message_json="$1"
    jq -nc '
        def evidence_map($blocks):
          [ $blocks[]?
            | select((.type == "code") and (((.text // "") | startswith("```"))))
            | select((.text // "") | test("evidence_map"))
            | ((.text // "") | split("\n") | .[1:-1] | join("\n") | (try (fromjson) catch []))
          ] | (.[0] // []);

        ($message.content // []) as $blocks |
        evidence_map($blocks) as $emap |
        [ range(0; $blocks | length) as $i |
          {
            index: $i,
            text: ($blocks[$i].text // ""),
            normalized: (($blocks[$i].text // "") | gsub("\\s+"; " ") | gsub("^ "; "") | gsub(" $"; "")),
            citations: ($blocks[$i].citations // []),
            evidence: ($emap[$i] // {})
          }
        ]
        | map(select(((.citations | length) > 0) or ((.evidence | length) > 0)))
        | .[]?
    ' --argjson message "$message_json"
}

build_evidence_from_message() {
    local session_dir="$1"
    local message_json="$2"

    if [[ -z "$message_json" || "$message_json" == "{}" ]]; then
        jq -n '{claims: [], sources: []}'
        return
    fi

    local manifest_path="$session_dir/cache/webfetch/index.json"
    local manifest_json="{}"
    if [[ -f "$manifest_path" ]]; then
        manifest_json=$(cat "$manifest_path")
    fi

    local sources_file claims_file
    sources_file=$(mktemp)
    claims_file=$(mktemp)

    declare -A source_map=()
    local source_count=0
    local claim_count=0

    mapfile -t block_entries < <(parse_block_entries "$message_json")

    local entry
    for entry in "${block_entries[@]}"; do
        local idx
        idx=$(jq -r '.index' <<<"$entry")
        local block_text
        block_text=$(jq -r '.normalized // ""' <<<"$entry")
        local evidence_entry
        evidence_entry=$(jq -c '.evidence // {}' <<<"$entry")
        local marker
        marker=$(jq -r '(.marker // .id // empty)' <<<"$evidence_entry")
        if [[ -z "$marker" || "$marker" == "null" ]]; then
            marker=$((idx + 1))
        fi
        local claim_text
        claim_text=$(jq -r '(.claim // empty)' <<<"$evidence_entry")
        if [[ -z "$claim_text" || "$claim_text" == "null" ]]; then
            claim_text="$block_text"
        fi
        local why_supported
        why_supported=$(jq -r '(.why_supported // "Source excerpt supports the statement.")' <<<"$evidence_entry")
        local confidence
        confidence=$(jq -r '(.confidence // empty)' <<<"$evidence_entry")

        mapfile -t citations < <(jq -c '.citations[]?' <<<"$entry")
        local claim_sources=()
        local citation_json
        for citation_json in "${citations[@]}"; do
            local raw_url
            raw_url=$(jq -r '.url // ""' <<<"$citation_json")
            read -r normalized kind <<<"$(normalize_source_url "$raw_url" "$session_dir")"
            if [[ -z "$normalized" ]]; then
                continue
            fi
            local title
            title=$(jq -r '.title // ""' <<<"$citation_json")
            local quoted
            quoted=$(jq -r '.cited_text // ""' <<<"$citation_json")
            local manifest_key="$raw_url"
            if [[ "$kind" == "web" ]]; then
                manifest_key="$normalized"
            fi
            local manifest_entry
            manifest_entry=$(lookup_manifest_entry "$manifest_json" "$manifest_key" "$kind")
            local body_file
            body_file=$(jq -r '.body_file // ""' <<<"$manifest_entry")
            local body_path=""
            if [[ -n "$body_file" ]]; then
                body_path="$session_dir/cache/webfetch/$body_file"
            fi
            local location_meta
            location_meta=$(compute_location_metadata "$body_path" "$quoted")
            [[ -z "$location_meta" ]] && location_meta='{}'
            local retrieved_at
            retrieved_at=$(jq -r '.fetched_at // empty' <<<"$manifest_entry")
            if [[ -z "$retrieved_at" ]]; then
                retrieved_at=$(jq -r '.retrieved_at // empty' <<<"$citation_json")
            fi
            local deep_link
            deep_link=$(build_text_fragment "$normalized" "$quoted" "${body_text:-}")
            local key="${normalized}||${title}||${quoted}"
            local source_id
            if [[ -n "${source_map[$key]:-}" ]]; then
                source_id="${source_map[$key]}"
            else
                source_count=$((source_count + 1))
                source_id="source_${source_count}"
                source_map["$key"]="$source_id"
                append_source_json "$sources_file" "$source_id" "$normalized" "$title" "$quoted" "$deep_link" "$retrieved_at" "$location_meta"
            fi
            claim_sources+=("$source_id")
        done

        if [[ ${#claim_sources[@]} -eq 0 ]]; then
            mapfile -t extra_sources < <(jq -r '.source_ids[]? // empty' <<<"$evidence_entry")
            if [[ ${#extra_sources[@]} -gt 0 ]]; then
                claim_sources+=("${extra_sources[@]}")
            fi
        fi

        if [[ ${#claim_sources[@]} -eq 0 ]]; then
            continue
        fi

        claim_count=$((claim_count + 1))
        local claim_sources_json
        claim_sources_json=$(printf '%s\n' "${claim_sources[@]}" | jq -R 'select(length>0)' | jq -s 'map(.)')
        jq -n \
            --arg id "claim_${claim_count}" \
            --arg marker "$marker" \
            --arg claim_text "$claim_text" \
            --arg why "$why_supported" \
            --arg confidence "$confidence" \
            --argjson sources "$claim_sources_json" \
            --arg drop_null_confidence "false" '
            {
              id: $id,
              marker: $marker,
              claim_text: ($claim_text | select(length>0)),
              why_supported: ($why | select(length>0)),
              sources: $sources
            }
            | with_entries(select(.value != null))
            | .confidence = (if $confidence == "" or $confidence == "null" then null else ($confidence | tonumber? // $confidence) end)
            | if ($drop_null_confidence == "true" and .confidence == null) then del(.confidence) else . end
        ' >> "$claims_file"
    done

    local claims_array
    claims_array=$(collect_array "$claims_file")
    local sources_array
    sources_array=$(collect_array "$sources_file")

    rm -f "$claims_file" "$sources_file"

    jq -n --argjson claims "$claims_array" --argjson sources "$sources_array" '{claims: $claims, sources: $sources}'
}

write_evidence_file() {
    local target="$1"
    local mode="$2"
    local transcript_path="$3"
    local evidence_json="$4"

    local generated_at
    generated_at=$(get_timestamp)
    local metadata
    if [[ -n "$transcript_path" ]]; then
        metadata=$(jq -n --arg path "$transcript_path" '{transcript_path: $path}')
    else
        metadata='{}'
    fi

    jq -n \
        --arg generated_at "$generated_at" \
        --arg mode "$mode" \
        --argjson evidence "$evidence_json" \
        --argjson metadata "$metadata" '
        {
          generated_at: $generated_at,
          mode: $mode,
          claims: ($evidence.claims // []),
          sources: ($evidence.sources // []),
          metadata: $metadata
        }
    ' > "$target"
}

main() {
    local mode
    mode=$(get_mode)
    if [[ "$mode" == "disabled" ]]; then
        return 0
    fi

    local session_dir_env="${CCONDUCTOR_SESSION_DIR:-}"
    if [[ -z "$session_dir_env" ]]; then
        return 0
    fi
    local session_dir
    session_dir=$(cd "$session_dir_env" 2>/dev/null && pwd)
    if [[ -z "$session_dir" ]]; then
        return 0
    fi

    local payload
    payload=$(read_payload)

    local evidence
    evidence=$(build_evidence_from_findings "$session_dir")
    local claim_count
    claim_count=$(jq '.claims | length' <<<"$evidence")

    local transcript_path=""
    if [[ "$claim_count" -eq 0 ]]; then
        transcript_path=$(jq -r '.transcript_path // ""' <<<"$payload")
        if [[ -z "$transcript_path" || ! -f "$transcript_path" ]]; then
            return 0
        fi
        local message_json
        message_json=$(find_latest_assistant_message "$transcript_path")
        if [[ -z "$message_json" || "$message_json" == "{}" ]]; then
            return 0
        fi
        evidence=$(build_evidence_from_message "$session_dir" "$message_json")
        claim_count=$(jq '.claims | length' <<<"$evidence")
        if [[ "$claim_count" -eq 0 ]]; then
            return 0
        fi
    else
        transcript_path=""
    fi

    local evidence_dir="$session_dir/evidence"
    mkdir -p "$evidence_dir"
    local evidence_file="$evidence_dir/evidence.json"

    write_evidence_file "$evidence_file" "$mode" "$transcript_path" "$evidence"
    return 0
}

main "$@"
