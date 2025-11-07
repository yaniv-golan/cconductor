#!/usr/bin/env bash
# Mission State Builder - Constructs mission state summary for orchestrator

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/budget-tracker.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$SCRIPT_DIR/stakeholder-classifier-state.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/invoke-agent.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/agent-registry.sh" 2>/dev/null || true

# Initialize agent registry if available (needed for watch-topic-evaluator setup)
if declare -F agent_registry_init >/dev/null 2>&1; then
    agent_registry_init
fi

BASH_RUNTIME="${CCONDUCTOR_BASH_RUNTIME:-$(command -v bash)}"

WATCH_TOPIC_STOPWORDS_REGEX='^(a|an|and|are|as|at|be|by|for|from|in|into|is|it|its|of|on|or|over|the|their|there|to|with|within|without)$'

watch_topic_canonicalize_token() {
    local token="$1"
    local base="$token"
    if [[ ${#base} -gt 4 && "$base" == *ies ]]; then
        base="${base%ies}y"
    elif [[ ${#base} -gt 3 && "$base" == *ing ]]; then
        base="${base%ing}"
    elif [[ ${#base} -gt 3 && "$base" == *ed ]]; then
        base="${base%ed}"
    elif [[ ${#base} -gt 3 && "$base" == *es ]]; then
        base="${base%es}"
    elif [[ ${#base} -gt 3 && "$base" == *s ]]; then
        base="${base%s}"
    fi
    if [[ ${#base} -gt 4 && "$base" == *ism ]]; then
        base="${base%ism}"
    fi
    if [[ ${#base} -gt 4 && "$base" == *ic ]]; then
        base="${base%ic}"
    fi
    printf '%s' "$base"
}

watch_topic_tokenize_text() {
    local text="$1"
    local normalized
    normalized=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n')
    local -a tokens=()
    while IFS= read -r token; do
        [[ -z "$token" ]] && continue
        if [[ "$token" =~ $WATCH_TOPIC_STOPWORDS_REGEX ]]; then
            continue
        fi
        token=$(watch_topic_canonicalize_token "$token")
        [[ -z "$token" ]] && continue
        local found=0
        if (( ${#tokens[@]} > 0 )); then
            for existing in "${tokens[@]}"; do
                if [[ "$existing" == "$token" ]]; then
                    found=1
                    break
                fi
            done
        fi
        if (( found == 0 )); then
            tokens+=("$token")
        fi
    done <<< "$normalized"
    if (( ${#tokens[@]} == 0 )); then
        printf ''
    else
        printf '%s\n' "${tokens[@]}"
    fi
}

watch_topic_ratio() {
    local numerator="$1"
    local denominator="$2"
    awk -v num="$numerator" -v den="$denominator" 'BEGIN {
        if (den <= 0) {
            printf "0"
        } else {
            printf "%.4f", (num / den)
        }
    }'
}

watch_topic_compute_jaccard() {
    local tokens_a_str="$1"
    local tokens_b_str="$2"
    local token
    local -a tokens_a=()
    local -a tokens_b=()
    if [[ -n "$tokens_a_str" ]]; then
        while IFS= read -r token; do
            [[ -z "$token" ]] && continue
            tokens_a+=("$token")
        done <<< "$tokens_a_str"
    fi
    if [[ -n "$tokens_b_str" ]]; then
        while IFS= read -r token; do
            [[ -z "$token" ]] && continue
            tokens_b+=("$token")
        done <<< "$tokens_b_str"
    fi
    local union=${#tokens_b[@]}
    local intersection=0
    if (( ${#tokens_a[@]} > 0 )); then
        for token in "${tokens_a[@]}"; do
            local found=0
            for existing in "${tokens_b[@]}"; do
                if [[ "$existing" == "$token" ]]; then
                    found=1
                    break
                fi
            done
            if (( found == 1 )); then
                ((intersection++))
            else
                ((union++))
            fi
        done
    fi
    if (( union == 0 )); then
        echo "0"
        return
    fi
    watch_topic_ratio "$intersection" "$union"
}

watch_topic_compute_coverage() {
    local canonical_tokens_str="$1"
    local claim_tokens_str="$2"
    local token
    local -a canonical_tokens=()
    local -a claim_tokens=()
    if [[ -n "$canonical_tokens_str" ]]; then
        while IFS= read -r token; do
            [[ -z "$token" ]] && continue
            canonical_tokens+=("$token")
        done <<< "$canonical_tokens_str"
    fi
    if [[ -n "$claim_tokens_str" ]]; then
        while IFS= read -r token; do
            [[ -z "$token" ]] && continue
            claim_tokens+=("$token")
        done <<< "$claim_tokens_str"
    fi
    local total=${#canonical_tokens[@]}
    if (( total == 0 )); then
        echo "0"
        return
    fi
    local hits=0
    for token in "${canonical_tokens[@]}"; do
        local found=0
        for candidate in "${claim_tokens[@]}"; do
            if [[ "$candidate" == "$token" ]]; then
                found=1
                break
            fi
        done
        if (( found == 1 )); then
            ((hits++))
        fi
    done
    watch_topic_ratio "$hits" "$total"
}

watch_topic_score_ge() {
    local score="${1:-0}"
    local threshold="${2:-0}"
    awk -v s="$score" -v t="$threshold" 'BEGIN {
        if (s+0 >= t+0) { exit 0 } else { exit 1 }
    }'
}

watch_topic_sanitize_threshold() {
    local candidate="$1"
    local fallback="$2"
    if [[ "$candidate" =~ ^([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]]; then
        echo "$candidate"
    else
        echo "$fallback"
    fi
}

to_session_relative() {
    local path="$1"
    local session_dir="$2"
    if [[ -z "$path" || "$path" == "null" ]]; then
        echo ""
        return 0
    fi
    if [[ "$path" != /* ]]; then
        echo "$path"
        return 0
    fi
    local normalized_session="${session_dir%/}"
    if [[ "$path" == "$normalized_session" ]]; then
        echo "."
        return 0
    fi
    if [[ "$path" == "$normalized_session/"* ]]; then
        local rel="${path#"$normalized_session/"}"
        printf '%s\n' "${rel:-.}"
        return 0
    fi
    echo "$path"
}

stat_mtime() {
    local path="$1"
    if [[ ! -e "$path" ]]; then
        echo ""
        return 0
    fi
    if stat -f '%m' "$path" >/dev/null 2>&1; then
        stat -f '%m' "$path" 2>/dev/null || echo ""
    elif stat -c '%Y' "$path" >/dev/null 2>&1; then
        stat -c '%Y' "$path" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

epoch_to_iso8601() {
    local epoch="$1"
    if [[ -z "$epoch" || "$epoch" == "0" || "$epoch" == "null" ]]; then
        echo ""
        return 0
    fi
    if date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
        date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ'
    elif date -u -d "@$epoch" '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
        date -u -d "@$epoch" '+%Y-%m-%dT%H:%M:%SZ'
    else
        echo ""
    fi
}

# Filter candidate claims for LLM evaluation
# Returns claims with coverage >= threshold but < full threshold
watch_topic_filter_candidate_claims() {
    local topic_json="$1"
    local claims_json="$2"
    local session_dir="$3"
    
    # Extract watch topic canonical text
    local canonical
    canonical=$(safe_jq_from_json "$topic_json" '.canonical // .text // ""' "" "$session_dir" "watch_topic_llm.canonical")
    
    if [[ -z "$canonical" ]]; then
        echo '[]'
        return 0
    fi
    
    # Tokenize watch topic
    local watch_tokens
    watch_tokens=$(watch_topic_tokenize_text "$canonical")
    
    # Filter claims with coverage >= 0.25 (configurable)
    local min_coverage="${WATCH_TOPIC_LLM_CANDIDATE_MIN:-0.25}"
    local full_coverage="${WATCH_TOPIC_COVERAGE_CRITICAL_MIN:-0.65}"
    local full_jaccard="${WATCH_TOPIC_JACCARD_CRITICAL_MIN:-0.15}"
    local -a candidates=()
    
    # Parse claims array and filter
    while IFS= read -r claim_json; do
        [[ -z "$claim_json" || "$claim_json" == "null" ]] && continue
        
        # Extract claim text
        local claim_text
        claim_text=$(safe_jq_from_json "$claim_json" '.statement // .text // ""' "" "$session_dir" "watch_topic_llm.claim_text")
        [[ -z "$claim_text" ]] && continue
        
        # Compute lexical scores
        local claim_tokens
        claim_tokens=$(watch_topic_tokenize_text "$claim_text")
        
        local coverage
        coverage=$(watch_topic_compute_coverage "$watch_tokens" "$claim_tokens")
        
        local jaccard
        jaccard=$(watch_topic_compute_jaccard "$watch_tokens" "$claim_tokens")
        
        # Skip if already meets full thresholds (will be caught by lexical matching)
        if watch_topic_score_ge "$jaccard" "$full_jaccard" || watch_topic_score_ge "$coverage" "$full_coverage"; then
            continue
        fi
        
        # Include if meets minimum coverage threshold
        if watch_topic_score_ge "$coverage" "$min_coverage"; then
            # Enrich with lexical scores for LLM context
            local enriched
            enriched=$(safe_jq_from_json "$claim_json" '.' '{}' "$session_dir" "watch_topic_llm.enriched_claim" false)
            enriched=$(echo "$enriched" | jq \
                --argjson cov "$coverage" \
                --argjson jac "$jaccard" \
                '. + {lexical_coverage: $cov, lexical_jaccard: $jac}')
            candidates+=("$enriched")
        fi
        
    done < <(echo "$claims_json" | jq -c '.[]')
    
    # Return filtered array as JSON
    if (( ${#candidates[@]} == 0 )); then
        echo '[]'
    else
        printf '%s\n' "${candidates[@]}" | jq -s '.'
    fi
}

# Evaluate a single watch topic against candidate claims using LLM
watch_topic_llm_evaluate_single() {
    local session_dir="$1"
    local topic_json="$2"
    local candidate_claims_json="$3"
    
    # Extract topic details
    local topic_id
    topic_id=$(safe_jq_from_json "$topic_json" '.id // ""' "" "$session_dir" "watch_topic_llm.topic_id")
    local topic_text
    topic_text=$(safe_jq_from_json "$topic_json" '.canonical // .text // ""' "" "$session_dir" "watch_topic_llm.topic_text")
    local topic_variants
    topic_variants=$(safe_jq_from_json "$topic_json" '.variants // [] | join(", ")' "" "$session_dir" "watch_topic_llm.topic_variants")
    
    # Check Claude CLI availability
    if ! check_claude_cli; then
        log_warn "Claude CLI not available for LLM semantic matching"
        echo "{\"watch_topic_id\":\"$topic_id\",\"status\":\"pending\",\"matched_claims\":[],\"error\":\"LLM unavailable\"}"
        return 1
    fi
    
    # Count candidates
    local candidate_count
    candidate_count=$(echo "$candidate_claims_json" | jq 'length')
    
    # Format claims list
    local claims_list
    claims_list=$(echo "$candidate_claims_json" | jq -r 'to_entries | map("- [\(.key + 1)] (ID: \(.value.id // "unknown")): \(.value.statement // .value.text // "")") | join("\n")')
    
    # Build task input for agent
    local input_file
    input_file=$(mktemp "$session_dir/.watch-topic-input.XXXXXX")
    
    cat > "$input_file" <<EOF
**Watch Topic:** ${topic_text}
**Variants:** ${topic_variants:-none}

**Claims to evaluate:**
${claims_list}
EOF
    
    # Invoke agent using invoke_agent_v2
    local output_file
    output_file=$(mktemp "$session_dir/.watch-topic-output.XXXXXX")
    
    local start_time
    start_time=$(get_epoch)
    
    # Setup agent in session if not already there
    local agent_file="$session_dir/.claude/agents/watch-topic-evaluator.json"
    if [[ ! -f "$agent_file" ]]; then
        # Check if agent exists in registry
        if command -v agent_registry_exists >/dev/null 2>&1 && agent_registry_exists "watch-topic-evaluator"; then
            local agent_metadata
            agent_metadata=$(agent_registry_get "watch-topic-evaluator")
            
            # Load system prompt
            local agent_dir
            agent_dir=$(dirname "$agent_metadata")
            local system_prompt
            system_prompt=$(cat "$agent_dir/system-prompt.md" 2>/dev/null || echo "")
            
            if [[ -n "$system_prompt" ]]; then
                # Get model from agent metadata or use default
                local agent_model
                agent_model=$(safe_jq_from_file "$agent_metadata" '.model // "claude-haiku-4"' "claude-haiku-4" "$session_dir" "watch_topic_llm.agent_model")
                
                # Create agent definition
                mkdir -p "$session_dir/.claude/agents"
                jq -n \
                    --arg prompt "$system_prompt" \
                    --arg model "$agent_model" \
                    '{
                        "systemPrompt": $prompt,
                        "model": $model
                    }' > "$agent_file"
            else
                log_warn "Watch topic evaluator system prompt not found"
                rm -f "$input_file" "$output_file"
                echo "{\"watch_topic_id\":\"$topic_id\",\"status\":\"pending\",\"matched_claims\":[],\"error\":\"Agent setup failed: system prompt not found\"}"
                return 1
            fi
        else
            log_warn "Watch topic evaluator not found in registry"
            rm -f "$input_file" "$output_file"
            echo "{\"watch_topic_id\":\"$topic_id\",\"status\":\"pending\",\"matched_claims\":[],\"error\":\"Agent setup failed: not found in registry\"}"
            return 1
        fi
    fi
    
    # Use invoke_agent_v2 with watch-topic-evaluator agent
    if ! invoke_agent_v2 "watch-topic-evaluator" "$input_file" "$output_file" 30 "$session_dir" ""; then
        local error_msg="Agent invocation failed"
        log_warn "LLM evaluation failed for watch topic $topic_id: ${error_msg}"
        rm -f "$input_file" "$output_file"
        echo "{\"watch_topic_id\":\"$topic_id\",\"status\":\"pending\",\"matched_claims\":[],\"error\":\"${error_msg}\"}"
        return 1
    fi
    
    local end_time
    end_time=$(get_epoch)
    local duration=$((end_time - start_time))
    local duration_ms=$((duration * 1000))
    
    # Extract cost using existing helper
    local cost_usd
    cost_usd=$(extract_cost_from_output "$output_file")
    
    # Parse result using existing JSON extraction helper
    local result
    result=$(extract_json_from_agent_output "$output_file" true 2>/dev/null || echo '{}')
    
    # Validate result structure
    if [[ -z "$result" || "$result" == "{}" ]]; then
        log_warn "LLM returned empty result for watch topic $topic_id"
        rm -f "$input_file" "$output_file"
        echo "{\"watch_topic_id\":\"$topic_id\",\"status\":\"pending\",\"matched_claims\":[],\"error\":\"Empty LLM response\"}"
        return 1
    fi
    
    # Extract metrics for logging
    local matches_found
    matches_found=$(echo "$result" | jq '.matched_claims | length' 2>/dev/null || echo "0")
    local best_confidence
    best_confidence=$(echo "$result" | jq '.matched_claims | map(.confidence) | max // 0' 2>/dev/null || echo "0")
    
    # Record cost to budget
    if command -v budget_record_llm_match >/dev/null 2>&1; then
        budget_record_llm_match "$session_dir" "$cost_usd" || true
    fi
    
    # Log to events.jsonl
    if [[ -d "$session_dir/logs" ]]; then
        mkdir -p "$session_dir/logs"
        local model="${WATCH_TOPIC_LLM_MODEL:-claude-haiku-4}"
        local event_json
        event_json=$(jq -nc \
            --arg type "watch_topic_llm_eval" \
            --arg topic_id "$topic_id" \
            --argjson claims_evaluated "$candidate_count" \
            --argjson matches_found "$matches_found" \
            --argjson best_confidence "$best_confidence" \
            --argjson duration_ms "$duration_ms" \
            --arg model "$model" \
            --argjson cost_usd "$cost_usd" \
            --arg timestamp "$(get_timestamp)" \
            '{
                type: $type,
                topic_id: $topic_id,
                claims_evaluated: $claims_evaluated,
                matches_found: $matches_found,
                best_confidence: $best_confidence,
                duration_ms: $duration_ms,
                model: $model,
                cost_usd: $cost_usd,
                timestamp: $timestamp
            }' 2>/dev/null || echo '{}')
        if [[ -n "$event_json" && "$event_json" != "{}" ]]; then
            echo "$event_json" >> "$session_dir/logs/events.jsonl" 2>/dev/null || true
        fi
    fi
    
    # Cleanup temp files
    rm -f "$input_file" "$output_file"
    
    # Return structured JSON
    echo "$result"
}

# Batch evaluate multiple watch topics using LLM semantic matching
watch_topic_llm_batch_evaluate() {
    local session_dir="$1"
    local watch_topics_json="$2"
    local claims_json="$3"
    
    # Iterate over watch topics
    local -a results=()
    
    while IFS= read -r topic_json; do
        [[ -z "$topic_json" || "$topic_json" == "null" ]] && continue
        
        # Filter candidate claims for this topic
        local candidate_claims
        candidate_claims=$(watch_topic_filter_candidate_claims "$topic_json" "$claims_json" "$session_dir")
        
        # Skip if no candidates
        local candidate_count
        candidate_count=$(echo "$candidate_claims" | jq 'length' 2>/dev/null || echo "0")
        if (( candidate_count == 0 )); then
            continue
        fi
        
        log_info "Evaluating watch topic with $candidate_count LLM candidates"
        
        # Evaluate with LLM
        local llm_result
        if llm_result=$(watch_topic_llm_evaluate_single "$session_dir" "$topic_json" "$candidate_claims"); then
            results+=("$llm_result")
        fi
        
    done < <(echo "$watch_topics_json" | jq -c '.[]')
    
    # Combine results
    if (( ${#results[@]} == 0 )); then
        echo '[]'
    else
        printf '%s\n' "${results[@]}" | jq -s '.'
    fi
}

build_mission_state() {
    local session_dir="$1"

    if [[ -z "$session_dir" || ! -d "$session_dir" ]]; then
        log_system_error "${session_dir:-unknown}" "build_mission_state" "Invalid session directory"
        return 1
    fi

    local meta_dir="$session_dir/meta"
    mkdir -p "$meta_dir"

    local kg_file="$session_dir/knowledge/knowledge-graph.json"
    local heuristics_file="$meta_dir/domain-heuristics.json"

    local claims_count="0"
    local entities_count="0"
    local sources_count="0"
    local kg_iteration="0"
    local kg_confidence_overall=""
    local kg_confidence_by_category="{}"
    if [[ -f "$kg_file" ]]; then
        claims_count=$(safe_jq_from_file "$kg_file" '.claims | length' '0' "$session_dir" "mission_state.claims")
        entities_count=$(safe_jq_from_file "$kg_file" '.entities | length' '0' "$session_dir" "mission_state.entities")
        sources_count=$(safe_jq_from_file "$kg_file" '[.claims[]? | .sources[]?] | unique_by(.url) | length' '0' "$session_dir" "mission_state.sources" "false")
        kg_iteration=$(safe_jq_from_file "$kg_file" '.iteration // 0' '0' "$session_dir" "mission_state.kg_iteration")
        kg_confidence_overall=$(safe_jq_from_file "$kg_file" '.confidence_scores.overall // ""' "" "$session_dir" "mission_state.confidence_overall")
        kg_confidence_by_category=$(safe_jq_from_file "$kg_file" '.confidence_scores.by_category // {}' '{}' "$session_dir" "mission_state.confidence_by_category" "false")
    fi
    local sources_total_numeric="${sources_count:-0}"
    sources_total_numeric=$((sources_total_numeric + 0))

    local waivers_file="$meta_dir/watch-topic-waivers.json"
    local watch_topic_waivers=""
    if [[ -f "$waivers_file" ]]; then
        while IFS= read -r waiver_id; do
            [[ -z "$waiver_id" || "$waiver_id" == "null" ]] && continue
            watch_topic_waivers+="$waiver_id"$'\n'
        done < <(jq -r '.[]?' "$waivers_file" 2>/dev/null || printf '')
    fi

    local kg_claims_json="[]"
    local -a kg_claim_entries=()
    if [[ -f "$kg_file" ]]; then
        kg_claims_json=$(safe_jq_from_file "$kg_file" '
            (.claims // []) | map({
                id: (.id // ""),
                statement: (.statement // "")
            })
        ' '[]' "$session_dir" "mission_state.claims_payload" false)
        if [[ -n "$kg_claims_json" && "$kg_claims_json" != "[]" ]]; then
            while IFS= read -r claim_entry; do
                [[ -z "$claim_entry" || "$claim_entry" == "null" ]] && continue
                kg_claim_entries+=("$claim_entry")
            done < <(jq -c '.[]' <<< "$kg_claims_json")
        fi
    fi

    local watch_status_json="[]"
    if [[ -f "$heuristics_file" ]]; then
        local watch_topics_source
        watch_topics_source=$(safe_jq_from_file "$heuristics_file" '.watch_topics // []' '[]' "$session_dir" "mission_state.watch_topics" false)

        if [[ -n "$watch_topics_source" && "$watch_topics_source" != "[]" ]]; then
            local -a watch_status_entries=()
            local base_jaccard_threshold
            base_jaccard_threshold=$(watch_topic_sanitize_threshold "${WATCH_TOPIC_JACCARD_MIN:-0.4}" "0.4")
            local base_coverage_threshold
            base_coverage_threshold=$(watch_topic_sanitize_threshold "${WATCH_TOPIC_COVERAGE_MIN:-0.65}" "0.65")

            while IFS= read -r topic_json; do
                [[ -z "$topic_json" || "$topic_json" == "null" ]] && continue

                local topic_importance
                topic_importance=$(safe_jq_from_json "$topic_json" '.importance // ""' "" "$session_dir" "mission_state.watch_topic.importance")
                local topic_importance_lc
                topic_importance_lc=$(printf '%s' "$topic_importance" | tr '[:upper:]' '[:lower:]')
                if [[ "$topic_importance_lc" != "critical" ]]; then
                    continue
                fi

                local topic_id
                topic_id=$(safe_jq_from_json "$topic_json" '.id // ""' "" "$session_dir" "mission_state.watch_topic.id")
                local canonical
                canonical=$(safe_jq_from_json "$topic_json" '.canonical // ""' "" "$session_dir" "mission_state.watch_topic.canonical")
                local variants_json
                variants_json=$(safe_jq_from_json "$topic_json" '.variants // []' '[]' "$session_dir" "mission_state.watch_topic.variants" false)

                local -a variant_terms=()
                if [[ -n "$canonical" ]]; then
                    variant_terms+=("$(printf '%s' "$canonical" | tr '[:upper:]' '[:lower:]')")
                fi
                if [[ -n "$variants_json" && "$variants_json" != "[]" ]]; then
                    while IFS= read -r variant_term; do
                        [[ -z "$variant_term" || "$variant_term" == "null" ]] && continue
                        variant_terms+=("$(printf '%s' "$variant_term" | tr '[:upper:]' '[:lower:]')")
                    done < <(jq -r '.[]?' <<< "$variants_json")
                fi

                local jaccard_threshold="$base_jaccard_threshold"
                local coverage_threshold="$base_coverage_threshold"
                if [[ "$topic_importance_lc" == "critical" ]]; then
                    jaccard_threshold=$(watch_topic_sanitize_threshold "${WATCH_TOPIC_JACCARD_CRITICAL_MIN:-0.15}" "$jaccard_threshold")
                    coverage_threshold=$(watch_topic_sanitize_threshold "${WATCH_TOPIC_COVERAGE_CRITICAL_MIN:-$coverage_threshold}" "$coverage_threshold")
                fi

                local status="pending"
                local -a matched_claim_ids=()
                if [[ -n "$topic_id" ]] && printf '%s' "$watch_topic_waivers" | grep -Fxq "$topic_id"; then
                    status="waived"
                else
                    local canonical_tokens_str=""
                    if [[ -n "$canonical" ]]; then
                        canonical_tokens_str=$(watch_topic_tokenize_text "$canonical")
                    fi
                    for claim_entry in "${kg_claim_entries[@]}"; do
                        local claim_statement
                        claim_statement=$(safe_jq_from_json "$claim_entry" '.statement // ""' "" "$session_dir" "mission_state.watch_topic.claim_statement")
                        [[ -z "$claim_statement" ]] && continue
                        local claim_statement_lc
                        claim_statement_lc=$(printf '%s' "$claim_statement" | tr '[:upper:]' '[:lower:]')
                        local claim_id
                        claim_id=$(safe_jq_from_json "$claim_entry" '.id // ""' "" "$session_dir" "mission_state.watch_topic.claim_id")
                        local claim_tokens
                        claim_tokens=$(watch_topic_tokenize_text "$claim_statement")
                        local coverage_score="0"
                        if [[ -n "$canonical_tokens_str" ]]; then
                            coverage_score=$(watch_topic_compute_coverage "$canonical_tokens_str" "$claim_tokens")
                        fi
                        local matched=0
                        for variant_term in "${variant_terms[@]}"; do
                            [[ -z "$variant_term" ]] && continue
                            if [[ "$claim_statement_lc" == *"$variant_term"* ]]; then
                                matched=1
                                break
                            fi
                            local variant_tokens
                            variant_tokens=$(watch_topic_tokenize_text "$variant_term")
                            local jaccard_score
                            jaccard_score=$(watch_topic_compute_jaccard "$variant_tokens" "$claim_tokens")
                            if watch_topic_score_ge "${jaccard_score:-0}" "$jaccard_threshold" || watch_topic_score_ge "${coverage_score:-0}" "$coverage_threshold"; then
                                matched=1
                                break
                            fi
                        done
                        if (( matched == 1 )); then
                            status="covered"
                            if [[ -n "$claim_id" ]]; then
                                matched_claim_ids+=("$claim_id")
                            fi
                            break
                        fi
                    done
                fi

                local matches_json="[]"
                if (( ${#matched_claim_ids[@]} > 0 )); then
                    matches_json=$(printf '%s\n' "${matched_claim_ids[@]}" | jq -R 'select(length>0)' | jq -s '.')
                fi

                local entry
                entry=$(jq -n \
                    --arg id "$topic_id" \
                    --arg canonical "$canonical" \
                    --arg importance "$topic_importance" \
                    --arg status "$status" \
                    --argjson matches "$matches_json" \
                    '{
                        id: $id,
                        canonical: $canonical,
                        importance: $importance,
                        status: $status,
                        matched_claim_ids: (if $matches == null then [] else $matches end)
                    }')
                watch_status_entries+=("$entry")
            done < <(jq -c '.[]' <<< "$watch_topics_source")

            if (( ${#watch_status_entries[@]} > 0 )); then
                watch_status_json=$(printf '%s\n' "${watch_status_entries[@]}" | jq -s '.')
            fi
            
            # LLM semantic matching for pending topics (Phase 1)
            if [[ "${WATCH_TOPIC_LLM_ENABLED:-1}" == "1" ]]; then
                # Collect topics still pending after lexical pass
                local pending_topics_json='[]'
                if (( ${#watch_status_entries[@]} > 0 )); then
                    pending_topics_json=$(printf '%s\n' "${watch_status_entries[@]}" | \
                        jq -s '[.[] | select(.status == "pending")]')
                fi
                
                local pending_count
                pending_count=$(echo "$pending_topics_json" | jq 'length' 2>/dev/null || echo "0")
                
                if (( pending_count > 0 )) && (( ${#kg_claim_entries[@]} > 0 )); then
                    log_info "Running LLM semantic matching for $pending_count pending watch topics"
                    
                    # Build claims JSON from kg_claim_entries
                    local claims_json
                    claims_json=$(printf '%s\n' "${kg_claim_entries[@]}" | jq -s '.')
                    
                    # Invoke LLM batch evaluation
                    local llm_results
                    if llm_results=$(watch_topic_llm_batch_evaluate "$session_dir" "$pending_topics_json" "$claims_json"); then
                        # Merge LLM results back into watch_status_entries
                        # Update status from pending to covered where LLM matched
                        local llm_count
                        llm_count=$(echo "$llm_results" | jq 'length' 2>/dev/null || echo "0")
                        
                        if (( llm_count > 0 )); then
                            # Process each LLM result
                            while IFS= read -r llm_result; do
                                [[ -z "$llm_result" || "$llm_result" == "null" ]] && continue
                                
                                local topic_id
                                topic_id=$(echo "$llm_result" | jq -r '.watch_topic_id // ""')
                                local llm_status
                                llm_status=$(echo "$llm_result" | jq -r '.status // "pending"')
                                
                                if [[ -n "$topic_id" && "$llm_status" == "covered" ]]; then
                                    # Extract matched claim IDs
                                    local matched_claim_ids
                                    matched_claim_ids=$(echo "$llm_result" | jq -c '[.matched_claims[].claim_id] // []')
                                    
                                    # Update the corresponding entry in watch_status_entries
                                    local -a updated_entries=()
                                    local matched=0
                                    
                                    for entry in "${watch_status_entries[@]}"; do
                                        local entry_id
                                        entry_id=$(echo "$entry" | jq -r '.id // ""')
                                        
                                        if [[ "$entry_id" == "$topic_id" ]]; then
                                            # Update this entry with LLM results
                                            local updated_entry
                                            updated_entry=$(echo "$entry" | jq \
                                                --arg status "$llm_status" \
                                                --argjson claim_ids "$matched_claim_ids" \
                                                '.status = $status | .matched_claim_ids = $claim_ids | .matched_by = "llm_semantic"')
                                            updated_entries+=("$updated_entry")
                                            matched=1
                                            log_info "Watch topic '$topic_id' matched via LLM semantic evaluation"
                                            
                                            # Log status change event
                                            if [[ -d "$session_dir/logs" ]]; then
                                                local status_change_event
                                                status_change_event=$(jq -nc \
                                                    --arg type "watch_topic_status_change" \
                                                    --arg topic_id "$topic_id" \
                                                    --arg old_status "pending" \
                                                    --arg new_status "covered" \
                                                    --arg method "llm_semantic" \
                                                    --arg timestamp "$(get_timestamp)" \
                                                    '{
                                                        type: $type,
                                                        topic_id: $topic_id,
                                                        old_status: $old_status,
                                                        new_status: $new_status,
                                                        method: $method,
                                                        timestamp: $timestamp
                                                    }' 2>/dev/null || echo '{}')
                                                if [[ -n "$status_change_event" && "$status_change_event" != "{}" ]]; then
                                                    echo "$status_change_event" >> "$session_dir/logs/events.jsonl" 2>/dev/null || true
                                                fi
                                            fi
                                        else
                                            updated_entries+=("$entry")
                                        fi
                                    done
                                    
                                    if (( matched == 1 )); then
                                        watch_status_entries=("${updated_entries[@]}")
                                    fi
                                fi
                            done < <(echo "$llm_results" | jq -c '.[]')
                            
                            # Rebuild watch_status_json with updated entries
                            if (( ${#watch_status_entries[@]} > 0 )); then
                                watch_status_json=$(printf '%s\n' "${watch_status_entries[@]}" | jq -s '.')
                            fi
                        fi
                    fi
                fi
            fi
            
            # Log final status for all watch topics
            if [[ -d "$session_dir/logs" ]] && (( ${#watch_status_entries[@]} > 0 )); then
                for entry in "${watch_status_entries[@]}"; do
                    local final_topic_id
                    final_topic_id=$(echo "$entry" | jq -r '.id // ""')
                    local final_status
                    final_status=$(echo "$entry" | jq -r '.status // "unknown"')
                    local final_method
                    final_method=$(echo "$entry" | jq -r '.matched_by // "lexical"')
                    
                    local final_status_event
                    final_status_event=$(jq -nc \
                        --arg type "watch_topic_final_status" \
                        --arg topic_id "$final_topic_id" \
                        --arg status "$final_status" \
                        --arg method "$final_method" \
                        --arg timestamp "$(get_timestamp)" \
                        '{
                            type: $type,
                            topic_id: $topic_id,
                            status: $status,
                            evaluation_path: [$method],
                            timestamp: $timestamp
                        }' 2>/dev/null || echo '{}')
                    if [[ -n "$final_status_event" && "$final_status_event" != "{}" ]]; then
                        echo "$final_status_event" >> "$session_dir/logs/events.jsonl" 2>/dev/null || true
                    fi
                done
            fi
        fi
    fi

    local classifier_file="$session_dir/session/stakeholder-classifications.jsonl"
    local classifier_path_rel=""
    local classifier_mtime=""
    local classifier_exists=0
    if [[ -f "$classifier_file" ]]; then
        classifier_exists=1
        classifier_path_rel="${classifier_file#"$session_dir/"}"
        if [[ "$classifier_path_rel" == "$classifier_file" ]]; then
            classifier_path_rel="$classifier_file"
        fi
        classifier_mtime=$(stat_mtime "$classifier_file")
    fi
    local classifier_updated_iso=""
    local classifier_total="0"
    local classifier_pending="$sources_total_numeric"
    local classifier_status="stale"
    local classifier_category_counts='{}'
    local classifier_needs_review_json='[]'
    local classifier_needs_review_count="0"
    local classifier_needs_review_pending_json='[]'
    local classifier_needs_review_pending_count="0"
    local classifier_needs_review_manual_json='[]'
    local classifier_needs_review_manual_count="0"
    local classifier_digest=""
    local classifier_diff_added=0
    local classifier_diff_removed=0
    if (( classifier_exists )); then
        classifier_total=$(jq -s 'map(select(.source_id != null)) | length' "$classifier_file" 2>/dev/null || echo "0")
        classifier_total=$((classifier_total + 0))
        classifier_pending=$((sources_total_numeric - classifier_total))
        if (( classifier_pending < 0 )); then
            classifier_pending=0
        fi
        classifier_category_counts=$(jq -s '
            reduce .[] as $row ({};
                ($row.resolved_category // "") as $cat |
                if ($cat | length) == 0 then .
                else . + {($cat): ((.[$cat] // 0) + 1)}
                end
            )' "$classifier_file" 2>/dev/null || echo '{}')
        classifier_needs_review_json=$(jq -s '
            [ .[] 
              | select((.resolved_category // "") == "needs_review")
              | {
                    source_id: (.source_id // ""),
                    url: (.url // ""),
                    notes: (.notes // ""),
                    resolver_path: (.resolver_path // ""),
                    llm_attempted: (.llm_attempted // false),
                    retry_count: (.retry_count // 0)
                }
            ]' "$classifier_file" 2>/dev/null || echo '[]')
        classifier_needs_review_count=$(printf '%s\n' "$classifier_needs_review_json" | jq 'length' 2>/dev/null || echo "0")
        # Split needs_review into pending (llm_attempted != true) and manual (llm_attempted == true)
        classifier_needs_review_pending_json=$(printf '%s\n' "$classifier_needs_review_json" | jq '[.[] | select((.llm_attempted // false) != true)]' 2>/dev/null || echo '[]')
        classifier_needs_review_pending_count=$(printf '%s\n' "$classifier_needs_review_pending_json" | jq 'length' 2>/dev/null || echo "0")
        classifier_needs_review_manual_json=$(printf '%s\n' "$classifier_needs_review_json" | jq '[.[] | select((.llm_attempted // false) == true)]' 2>/dev/null || echo '[]')
        classifier_needs_review_manual_count=$(printf '%s\n' "$classifier_needs_review_manual_json" | jq 'length' 2>/dev/null || echo "0")
        classifier_updated_iso=$(epoch_to_iso8601 "$classifier_mtime")
    fi

    local state_file="$session_dir/meta/stakeholder-classifier-state.json"
    local stored_digest=""
    local stored_sources_json='[]'
    local stored_count=0
    if [[ -s "$state_file" ]]; then
        stored_digest=$(jq -r '.kg_source_digest // ""' "$state_file" 2>/dev/null || echo "")
        stored_sources_json=$(jq -c '.sources // []' "$state_file" 2>/dev/null || echo '[]')
        stored_count=$(jq -r '.kg_source_count // 0' "$state_file" 2>/dev/null || echo "0")
    fi

    local sources_summary
    if sources_summary=$(stakeholder_classifier_collect_sources "$session_dir"); then
        classifier_digest=$(printf '%s\n' "$sources_summary" | jq -r '.digest // ""' 2>/dev/null || echo "")
        local current_sources_json
        current_sources_json=$(printf '%s\n' "$sources_summary" | jq -c '.sources // []' 2>/dev/null || echo '[]')
        if (( stored_count > 0 )) && (( stored_count == sources_total_numeric )); then
            stored_sources_json="$current_sources_json"
            if [[ -z "$stored_digest" ]]; then
                stored_digest="$classifier_digest"
            fi
        fi
        local diff_json
        diff_json=$(stakeholder_classifier_sources_diff "$stored_sources_json" "$current_sources_json")
        classifier_diff_added=$(printf '%s\n' "$diff_json" | jq '.added // 0' 2>/dev/null || echo "0")
        classifier_diff_removed=$(printf '%s\n' "$diff_json" | jq '.removed // 0' 2>/dev/null || echo "0")
        if [[ -s "$state_file" ]] && (( classifier_pending == 0 )) && (( classifier_needs_review_pending_count == 0 )) && (( stored_count == sources_total_numeric )); then
            classifier_diff_added=0
            classifier_diff_removed=0
            stored_sources_json="$current_sources_json"
            if [[ -z "$stored_digest" ]]; then
                stored_digest="$classifier_digest"
            fi
        fi
    fi

    if (( classifier_needs_review_pending_count > 0 )); then
        classifier_status="stale_pending"
    elif (( classifier_pending > 0 )); then
        classifier_status="stale_pending"
    elif (( sources_total_numeric == 0 )); then
        classifier_status="fresh"
    elif [[ -n "$classifier_digest" && -n "$stored_digest" && "$classifier_digest" == "$stored_digest" ]]; then
        classifier_status="fresh"
    elif [[ -n "$classifier_digest" ]]; then
        classifier_status="stale_digest_mismatch"
    else
        classifier_status="stale"
    fi

    local spent_usd="0"
    local spent_invocations="0"
    local elapsed_minutes="0"
    local budget_limit="0"
    local time_limit="9999"
    local invocation_limit="9999"
    if command -v budget_status >/dev/null 2>&1; then
        local budget_state
        budget_state=$(budget_status "$session_dir" 2>/dev/null || echo '{}')
        spent_usd=$(safe_jq_from_json "$budget_state" '.spent.cost_usd // 0' '0' "$session_dir" "mission_state.spent_usd")
        spent_invocations=$(safe_jq_from_json "$budget_state" '.spent.agent_invocations // 0' '0' "$session_dir" "mission_state.spent_invocations")
        elapsed_minutes=$(safe_jq_from_json "$budget_state" '.spent.elapsed_minutes // 0' '0' "$session_dir" "mission_state.elapsed_minutes")
        budget_limit=$(safe_jq_from_json "$budget_state" '.limits.budget_usd // 0' '0' "$session_dir" "mission_state.budget_limit")
        time_limit=$(safe_jq_from_json "$budget_state" '.limits.max_time_minutes // 9999' '9999' "$session_dir" "mission_state.max_time_minutes")
        invocation_limit=$(safe_jq_from_json "$budget_state" '.limits.max_agent_invocations // 9999' '9999' "$session_dir" "mission_state.max_invocations")
    else
        local budget_file="$meta_dir/budget.json"
        if [[ -f "$budget_file" ]]; then
            spent_usd=$(json_get_field "$budget_file" '.spent.cost_usd' '0')
            spent_invocations=$(json_get_field "$budget_file" '.spent.agent_invocations' '0')
            elapsed_minutes=$(json_get_field "$budget_file" '.spent.elapsed_minutes' '0')
            budget_limit=$(json_get_field "$budget_file" '.limits.budget_usd' '0')
            time_limit=$(json_get_field "$budget_file" '.limits.max_time_minutes' '9999')
            invocation_limit=$(json_get_field "$budget_file" '.limits.max_agent_invocations' '9999')
        fi
    fi

    local qg_summary="$session_dir/artifacts/quality-gate-summary.json"
    local qg_status="not_run"
    if [[ -f "$qg_summary" ]]; then
        qg_status=$(json_get_field "$qg_summary" '.status' 'unknown')
    fi

    local compliance_json='{}'
    if [[ -f "$heuristics_file" && -f "$SCRIPT_DIR/domain-compliance-check.sh" ]]; then
        compliance_json=$("$BASH_RUNTIME" "$SCRIPT_DIR/domain-compliance-check.sh" "$session_dir" 2>/dev/null || echo '{}')
    fi

    local orch_log="$session_dir/logs/orchestration.jsonl"
    local recent_decisions='[]'
    if [[ -f "$orch_log" ]]; then
        local decision_tail
        decision_tail=$(tail -5 "$orch_log" 2>/dev/null || true)
        if [ -n "$decision_tail" ]; then
            if recent_decisions=$(printf '%s\n' "$decision_tail" | jq -s '.' 2>/dev/null); then
                :
            else
                recent_decisions='[]'
            fi
        else
            recent_decisions='[]'
        fi
    fi

    local orchestration_state_file="$session_dir/meta/orchestration-state.json"
    local synthesis_blockers_raw='[]'
    local synthesis_blocker_tags='[]'
    local synthesis_ready_bool="true"
    local synthesis_attempts_value="0"
    if [[ -f "$orchestration_state_file" ]]; then
        synthesis_blockers_raw=$(safe_jq_from_file "$orchestration_state_file" '.synthesis_blockers // []' '[]' "$session_dir" "mission_state.synthesis_blockers" false)
        synthesis_attempts_value=$(safe_jq_from_file "$orchestration_state_file" '.synthesis_attempts // 0' '0' "$session_dir" "mission_state.synthesis_attempts")
    fi
    if [[ -z "$synthesis_blockers_raw" || "$synthesis_blockers_raw" == "null" ]]; then
        synthesis_blockers_raw='[]'
    fi
    if [[ -z "$synthesis_attempts_value" || "$synthesis_attempts_value" == "null" ]]; then
        synthesis_attempts_value="0"
    fi
    synthesis_attempts_value=$((synthesis_attempts_value + 0))

    local synthesis_blocker_count
    synthesis_blocker_count=$(printf '%s\n' "$synthesis_blockers_raw" | jq 'length' 2>/dev/null || echo "0")
    if (( synthesis_blocker_count > 0 )); then
        synthesis_ready_bool="false"
        synthesis_blocker_tags=$(printf '%s\n' "$synthesis_blockers_raw" | jq -c '
            def topic_label($topic):
                if $topic == null then
                    "unknown"
                elif ($topic | type) == "object" then
                    ($topic.canonical // $topic.id // ($topic | tostring))
                else
                    ($topic | tostring)
                end;
            (reduce .[] as $b ([];
                ($b.type // "") as $type
                | if $type == "watch_topics" then
                    if (($b.details.pending // []) | length) > 0 then
                        reduce ($b.details.pending // [])[] as $topic (.;
                            . + ["watch_topics:" + topic_label($topic)]
                        )
                    else
                        . + ["watch_topics"]
                    end
                else
                    . + [(if $type == "" then "unknown" else $type end)]
                end
            )) | unique
        ' 2>/dev/null || echo '[]')
        if [[ -z "$synthesis_blocker_tags" || "$synthesis_blocker_tags" == "null" ]]; then
            synthesis_blocker_tags='[]'
        fi
    else
        synthesis_blocker_tags='[]'
    fi

    local tmp_file="$meta_dir/mission_state.json.tmp"
    local kg_path_rel
    kg_path_rel=$(to_session_relative "$kg_file" "$session_dir")
    local log_path_rel
    log_path_rel=$(to_session_relative "$orch_log" "$session_dir")
    jq -n \
        --argjson claims "$claims_count" \
        --argjson entities "$entities_count" \
        --argjson sources "$sources_count" \
        --arg spent "$spent_usd" \
        --argjson spent_inv "$spent_invocations" \
        --arg elapsed_min "$elapsed_minutes" \
        --arg budget_limit "$budget_limit" \
        --arg time_limit "$time_limit" \
        --arg invocation_limit "$invocation_limit" \
        --arg qg "$qg_status" \
        --argjson compliance "$compliance_json" \
        --argjson decisions "$recent_decisions" \
        --arg iteration_value "$kg_iteration" \
        --arg confidence_overall "$kg_confidence_overall" \
        --argjson confidence_by_category "$kg_confidence_by_category" \
        --argjson watch_topics "$watch_status_json" \
        --arg classifier_path "${classifier_path_rel:-}" \
        --arg classifier_status "${classifier_status:-stale}" \
        --arg classifier_digest "${classifier_digest:-}" \
        --arg classifier_updated_iso "${classifier_updated_iso:-}" \
        --arg classifier_updated_epoch "${classifier_mtime:-}" \
        --argjson classifier_total "${classifier_total:-0}" \
        --argjson classifier_pending "${classifier_pending:-0}" \
        --argjson classifier_counts "$classifier_category_counts" \
        --argjson classifier_needs_review "$classifier_needs_review_json" \
        --argjson classifier_needs_review_count "$classifier_needs_review_count" \
        --argjson classifier_needs_review_pending "$classifier_needs_review_pending_json" \
        --argjson classifier_needs_review_pending_count "$classifier_needs_review_pending_count" \
        --argjson classifier_needs_review_manual "$classifier_needs_review_manual_json" \
        --argjson classifier_needs_review_manual_count "$classifier_needs_review_manual_count" \
        --argjson classifier_diff_added "$classifier_diff_added" \
        --argjson classifier_diff_removed "$classifier_diff_removed" \
        --arg kg_path "$kg_path_rel" \
        --arg kg_path_abs "$kg_file" \
        --arg log_path "$log_path_rel" \
        --arg log_path_abs "$orch_log" \
        --argjson synthesis_ready "$synthesis_ready_bool" \
        --argjson synthesis_blockers "$synthesis_blocker_tags" \
        --argjson synthesis_blockers_detail "$synthesis_blockers_raw" \
        --argjson synthesis_attempts "$synthesis_attempts_value" \
        '{
            coverage: {
                claims: ($claims | tonumber),
                entities: ($entities | tonumber),
                sources: ($sources | tonumber)
            },
            budget_summary: {
                spent_usd: ($spent | tonumber),
                spent_invocations: ($spent_inv | tonumber),
                elapsed_minutes: ($elapsed_min | tonumber),
                budget_usd: ($budget_limit | tonumber),
                max_time_minutes: ($time_limit | tonumber),
                max_agent_invocations: ($invocation_limit | tonumber)
            },
            quality_gate_status: $qg,
            domain_compliance: $compliance,
            last_5_decisions: $decisions,
            knowledge_progress: {
                iteration: ($iteration_value | tonumber? // 0),
                confidence: {
                    overall: (if ($confidence_overall | length) == 0 then null else ($confidence_overall | tonumber? // null) end),
                    by_category: $confidence_by_category
                }
            },
            synthesis: {
                ready: $synthesis_ready,
                attempts: ($synthesis_attempts | tonumber),
                blockers: $synthesis_blockers,
                blockers_detail: $synthesis_blockers_detail
            },
            stakeholder_classifier: {
                status: $classifier_status,
                classifications_file: (if $classifier_path == "" then null else $classifier_path end),
                total_classifications: $classifier_total,
                pending_sources: $classifier_pending,
                updated_at: (if $classifier_updated_iso == "" then null else $classifier_updated_iso end),
                updated_epoch: (if $classifier_updated_epoch == "" then null else ($classifier_updated_epoch | tonumber) end),
                source_digest: (if $classifier_digest == "" then null else $classifier_digest end),
                category_counts: $classifier_counts,
                needs_review: {
                    count: $classifier_needs_review_count,
                    entries: $classifier_needs_review,
                    pending: {
                        count: $classifier_needs_review_pending_count,
                        entries: $classifier_needs_review_pending
                    },
                    manual: {
                        count: $classifier_needs_review_manual_count,
                        entries: $classifier_needs_review_manual
                    }
                },
                coverage_delta: {
                    added: $classifier_diff_added,
                    removed: $classifier_diff_removed
                }
            },
            critical_watch_topics: $watch_topics,
            kg_path: $kg_path,
            kg_path_absolute: (if $kg_path_abs == "" then null else $kg_path_abs end),
            full_log_path: $log_path,
            full_log_path_absolute: (if $log_path_abs == "" then null else $log_path_abs end)
        }' >"$tmp_file"

    mv "$tmp_file" "$meta_dir/mission_state.json"
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" || -z "${BASH_SOURCE[0]:-}" ]]; then
    if [[ $# -ne 1 ]]; then
        echo "Usage: $0 <session_dir>" >&2
        exit 1
    fi
    build_mission_state "$1"
fi
