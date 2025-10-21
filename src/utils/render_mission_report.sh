#!/usr/bin/env bash
# Post-process mission reports by rendering evidence footnotes using jq data.
# Requires Bash 4.0+ for associative arrays used to track markers.

set -euo pipefail

if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
    echo "render_mission_report.sh requires Bash 4.0 or newer." >&2
    exit 1
fi

single_line() {
    local text="$1"
    printf '%s' "$text" | tr '\n' ' ' | tr -s '[:space:]' ' ' | sed -e 's/^ *//' -e 's/ *$//'
}

strip_section() {
    local heading="$1"
    # shellcheck disable=SC2016
    env TARGET_HEADING="$heading" perl -0pe '
        my $h = $ENV{TARGET_HEADING};
        if ($h && /\n## \Q$h\E\b/s) {
            s/\n## \Q$h\E\b.*//s;
        }
    '
}

convert_inline_references() {
    perl -0pe '
        my %allowed = map { $_ => 1 } grep { length } split(/\t/, $ENV{ALLOWED_MARKERS});
        s/\[(\d+)\]/$allowed{$1} ? "[^$1]" : $&/ge;
    '
}

rstrip_trailing_space() {
    perl -0pe 's/\s+\z//'
}

write_file_atomic() {
    local target="$1"
    shift || true
    local content="${1-}"
    if [[ -z "${content+x}" || -z "$content" ]]; then
        content="$(cat)"
    fi
    if [[ -n "$content" && "${content: -1}" != $'\n' ]]; then
        content="${content}"$'\n'
    fi
    local tmp
    tmp="$(mktemp "${target}.tmp.XXXX")"
    printf '%s' "$content" > "$tmp"
    mv "$tmp" "$target"
}

build_fallback_section() {
    local evidence_file="$1"
    local lines=()
    lines+=("## Evidence")
    lines+=("")

    local index=0
    while IFS= read -r claim_json; do
        ((index+=1))
        local claim_text
        claim_text=$(jq -r '.claim_text // .statement // ""' <<<"$claim_json")
        claim_text=$(single_line "$claim_text")
        [[ -z "$claim_text" ]] && continue

        lines+=("- ${claim_text}")

        local why_supported
        why_supported=$(jq -r '.why_supported // ""' <<<"$claim_json")
        why_supported=$(single_line "$why_supported")
        if [[ -n "$why_supported" ]]; then
            lines+=("  - Why: ${why_supported}")
        fi

        mapfile -t source_ids < <(jq -r '.sources[]? // empty' <<<"$claim_json")
        if [[ ${#source_ids[@]} -gt 0 ]]; then
            lines+=("  - Sources:")
            for source_id in "${source_ids[@]}"; do
                [[ -z "$source_id" ]] && continue
                local source_json
                source_json=$(jq -c --arg sid "$source_id" '.sources[]? | select(.id == $sid)' "$evidence_file")
                [[ -z "$source_json" ]] && continue
                local title url link quote descriptor
                title=$(jq -r '.title // ""' <<<"$source_json")
                url=$(jq -r '.url // ""' <<<"$source_json")
                link=$(jq -r '.deep_link // .url // ""' <<<"$source_json")
                quote=$(jq -r '.quote // ""' <<<"$source_json")
                quote=$(single_line "$quote")
                descriptor=""
                if [[ -n "$quote" ]]; then
                    descriptor=" — ${quote}"
                fi
                local label
                if [[ -n "$title" ]]; then
                    label="$title"
                elif [[ -n "$url" ]]; then
                    label="$url"
                else
                    label="Source"
                fi
                if [[ -n "$link" ]]; then
                    lines+=("    - [${label}](${link})${descriptor}")
                else
                    if [[ -n "$url" ]]; then
                        lines+=("    - ${url}${descriptor}")
                    else
                        lines+=("    - ${label}${descriptor}")
                    fi
                fi
            done
        fi
        lines+=("")
    done < <(jq -c '.claims[]?' "$evidence_file")

    printf '%s\n' "${lines[@]}" | rstrip_trailing_space
}


collect_markers() {
    local evidence_file="$1"
    local -n markers_ref="$2"
    local index=0
    while IFS= read -r claim_json; do
        ((index+=1))
        local marker
        marker=$(jq -r '(.marker // .id // "")' <<<"$claim_json")
        if [[ "$marker" == "null" || -z "$marker" ]]; then
            marker="$index"
        fi
        markers_ref+=("$marker")
    done < <(jq -c '.claims[]?' "$evidence_file")
}

build_footnotes() {
    local evidence_file="$1"
    local -n footnote_lines_ref="$2"

    declare -A seen_markers=()
    local index=0
    while IFS= read -r claim_json; do
        ((index+=1))
        local marker
        marker=$(jq -r '(.marker // .id // "")' <<<"$claim_json")
        if [[ "$marker" == "null" || -z "$marker" ]]; then
            marker="$index"
        fi
        if [[ -n "${seen_markers[$marker]+x}" ]]; then
            continue
        fi
        seen_markers["$marker"]=1
        markers_ref+=("$marker")

        local why_supported
        why_supported=$(jq -r '.why_supported // ""' <<<"$claim_json")
        why_supported=$(single_line "$why_supported")

        mapfile -t source_ids < <(jq -r '.sources[]? // empty' <<<"$claim_json")
        if [[ ${#source_ids[@]} -eq 0 ]]; then
            continue
        fi

        local summary="Evidence"
        local first_label=""
        local footnote_block=()

        for source_id in "${source_ids[@]}"; do
            [[ -z "$source_id" ]] && continue
            local source_json
            source_json=$(jq -c --arg sid "$source_id" '.sources[]? | select(.id == $sid)' "$evidence_file")
            [[ -z "$source_json" ]] && continue

            local title url link quote
            title=$(jq -r '.title // ""' <<<"$source_json")
            url=$(jq -r '.url // ""' <<<"$source_json")
            link=$(jq -r '.deep_link // .url // ""' <<<"$source_json")
            quote=$(jq -r '.quote // ""' <<<"$source_json")
            quote=$(single_line "$quote")

            if [[ -z "$first_label" ]]; then
                if [[ -n "$title" ]]; then
                    first_label="$title"
                elif [[ -n "$url" ]]; then
                    first_label="$url"
                else
                    first_label="Source"
                fi
                summary="Evidence from $first_label"
            fi

            if [[ -n "$quote" ]]; then
                footnote_block+=("> ${quote}")
                footnote_block+=("")
            fi

            local label
            if [[ -n "$title" ]]; then
                label="$title"
            elif [[ -n "$url" ]]; then
                label="$url"
            else
                label="Source"
            fi

            if [[ -n "$link" ]]; then
                footnote_block+=("Source: [${label}](${link})")
            elif [[ -n "$url" ]]; then
                footnote_block+=("Source: ${url}")
            else
                footnote_block+=("Source: ${label}")
            fi
            footnote_block+=("")
        done

        if [[ ${#footnote_block[@]} -eq 0 ]]; then
            continue
        fi

        footnote_lines_ref+=("[^${marker}]: <details><summary>${summary}</summary>")
        footnote_lines_ref+=("")
        for line in "${footnote_block[@]}"; do
            footnote_lines_ref+=("$line")
        done
        if [[ -n "$why_supported" ]]; then
            footnote_lines_ref+=("**Why this supports the claim:** ${why_supported}")
            footnote_lines_ref+=("")
        fi
        footnote_lines_ref+=("</details>")
        footnote_lines_ref+=("")
    done < <(jq -c '.claims[]?' "$evidence_file")
}

main() {
    if [[ "$#" -lt 1 ]]; then
        return 0
    fi

    local session_dir="$1"
    local report_path
    if [[ "$#" -ge 2 ]]; then
        report_path="$2"
    else
        report_path="$session_dir/final/mission-report.md"
    fi
    local evidence_path="$session_dir/evidence/evidence.json"

    local evidence_mode
    evidence_mode=$(printf '%s' "${CCONDUCTOR_EVIDENCE_MODE:-render}" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    [[ "$evidence_mode" == "disabled" ]] && return 0

    local render_mode
    render_mode=$(printf '%s' "${CCONDUCTOR_EVIDENCE_RENDER:-footnotes}" | tr '[:upper:]' '[:lower:]' | tr -d ' ')

    if [[ ! -f "$report_path" || ! -f "$evidence_path" ]]; then
        return 0
    fi

    local claim_count
    claim_count=$(jq '.claims | length' "$evidence_path" 2>/dev/null || echo 0)
    if [[ "$claim_count" -eq 0 ]]; then
        return 0
    fi

    local report_text
    report_text="$(cat "$report_path")"
    if [[ -z "$(printf '%s' "$report_text" | tr -d '[:space:]')" ]]; then
        return 0
    fi

    if [[ "$render_mode" != "fallback" ]] && printf '%s' "$report_text" | grep -q '\[\^'; then
        return 0
    fi

    local cleaned
    cleaned="$(printf '%s' "$report_text" | strip_section "Evidence Footnotes" | strip_section "Sources and Citations")"

    if [[ "$render_mode" == "fallback" ]]; then
        local restored
        restored="$(printf '%s' "$cleaned" | perl -0pe 's/\[\^(\d+)\]/[$1]/g' | rstrip_trailing_space)"
        local fallback_section
        fallback_section="$(build_fallback_section "$evidence_path")"
        if [[ -z "$fallback_section" ]]; then
            return 0
        fi
        local updated="${restored}\n\n${fallback_section}\n"
        printf '%b' "$updated" | write_file_atomic "$report_path"
        return 0
    fi

    local footnote_lines=()
    local markers=()
    collect_markers "$evidence_path" markers
    build_footnotes "$evidence_path" footnote_lines
    if [[ ${#footnote_lines[@]} -eq 0 ]]; then
        return 0
    fi

    local markers_env
    markers_env=$(IFS=$'\t'; printf '%s' "${markers[*]}")

    local converted
    ALLOWED_MARKERS="$markers_env"
    export ALLOWED_MARKERS
    converted="$(printf '%s' "$cleaned" | rstrip_trailing_space | convert_inline_references)"
    unset ALLOWED_MARKERS

    local footnote_block
    footnote_block="$(printf '%s\n' "${footnote_lines[@]}" | rstrip_trailing_space)"

    local updated_content
    updated_content="$(printf '%s\n\n## Evidence Footnotes\n\n%s\n' "$converted" "$footnote_block")"
    printf '%s' "$updated_content" | write_file_atomic "$report_path"
}

main "$@"
