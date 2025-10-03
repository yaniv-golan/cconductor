#!/bin/bash
# Contradiction Detector
# Identifies conflicting information in research findings

set -euo pipefail

# Detect contradictions in claims
detect_contradictions() {
    local kg_json="$1"

    local contradictions='[]'

    # Compare all pairs of claims for conflicts
    local claims_array
    claims_array=$(echo "$kg_json" | jq -c '.claims')
    local claim_count
    claim_count=$(echo "$claims_array" | jq 'length')

    for ((i=0; i<claim_count; i++)); do
        for ((j=i+1; j<claim_count; j++)); do
            local claim1
            claim1=$(echo "$claims_array" | jq ".[$i]")
            local claim2
            claim2=$(echo "$claims_array" | jq ".[$j]")

            local contradiction
            contradiction=$(compare_claims "$claim1" "$claim2")

            if [ "$contradiction" != "null" ]; then
                contradictions=$(echo "$contradictions" | jq --argjson con "$contradiction" '. += [$con]')
            fi
        done
    done

    echo "$contradictions"
}

# Compare two claims for contradiction
compare_claims() {
    local claim1_json="$1"
    local claim2_json="$2"

    local stmt1
    stmt1=$(echo "$claim1_json" | jq -r '.statement' | tr '[:upper:]' '[:lower:]')
    local stmt2
    stmt2=$(echo "$claim2_json" | jq -r '.statement' | tr '[:upper:]' '[:lower:]')
    local id1
    id1=$(echo "$claim1_json" | jq -r '.id')
    local id2
    id2=$(echo "$claim2_json" | jq -r '.id')

    # Contradiction indicators
    local contradicts=false

    # Check for negation patterns
    if echo "$stmt1" | grep -qE "(not|never|no|false)" && echo "$stmt2" | grep -qvE "(not|never|no|false)"; then
        # One is negated, other is not - potential contradiction
        local stmt1_normalized
        stmt1_normalized=$(echo "$stmt1" | sed 's/ not / /g; s/ never / /g; s/ no / /g')
        local stmt2_normalized
        stmt2_normalized=$(echo "$stmt2" | sed 's/ not / /g; s/ never / /g; s/ no / /g')

        if echo "$stmt1_normalized" | grep -qF "$stmt2_normalized" || echo "$stmt2_normalized" | grep -qF "$stmt1_normalized"; then
            contradicts=true
        fi
    fi

    # Check for contradictory terms
    if echo "$stmt1" | grep -qE "(always|must|required)" && echo "$stmt2" | grep -qE "(sometimes|optional|not required)"; then
        contradicts=true
    fi

    # Check for numeric contradictions
    local num1
    num1=$(echo "$stmt1" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
    local num2
    num2=$(echo "$stmt2" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)

    if [ -n "$num1" ] && [ -n "$num2" ]; then
        # If both have numbers and statements are similar, check if numbers differ significantly
        # Note: sed is needed here for complex regex pattern (numbers with optional decimals)
        local stmt1_no_num
        # shellcheck disable=SC2001
        stmt1_no_num=$(echo "$stmt1" | sed 's/[0-9]\+\(\.[0-9]\+\)\?//g')
        local stmt2_no_num
        # shellcheck disable=SC2001
        stmt2_no_num=$(echo "$stmt2" | sed 's/[0-9]\+\(\.[0-9]\+\)\?//g')

        if echo "$stmt1_no_num" | grep -qF "$stmt2_no_num" || echo "$stmt2_no_num" | grep -qF "$stmt1_no_num"; then
            # Same statement but different numbers
            if (( $(echo "$num1 != $num2" | bc -l 2>/dev/null || echo 0) )); then
                contradicts=true
            fi
        fi
    fi

    if [ "$contradicts" = true ]; then
        jq -n \
            --arg id1 "$id1" \
            --arg id2 "$id2" \
            --arg stmt1 "$stmt1" \
            --arg stmt2 "$stmt2" \
            --arg conflict "Statements appear to contradict each other" \
            '{
                claim1: $id1,
                claim2: $id2,
                conflict: $conflict,
                priority: 10,
                detected_at: (now | todateiso8601),
                status: "unresolved"
            }'
    else
        echo "null"
    fi
}

# Detect contradictions from agent outputs
detect_from_agent() {
    local agent_output="$1"

    # Look for explicitly reported contradictions
    echo "$agent_output" | jq '.contradictions_resolved // []'
}

# Generate investigation query for contradiction
generate_investigation_query() {
    local contradiction_json="$1"

    local claim1
    claim1=$(echo "$contradiction_json" | jq -r '.claim1')
    local claim2
    claim2=$(echo "$contradiction_json" | jq -r '.claim2')

    # Extract key terms from both claims
    local query="Investigate contradiction between claims: $claim1 vs $claim2. Which is correct?"

    echo "$query"
}

# Export functions
export -f detect_contradictions
export -f compare_claims
export -f detect_from_agent
export -f generate_investigation_query

# CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        detect)
            detect_contradictions "$(cat "$2")"
            ;;
        from-agent)
            detect_from_agent "$(cat "$2")"
            ;;
        query)
            generate_investigation_query "$(cat "$2")"
            ;;
        *)
            echo "Usage: $0 {detect|from-agent|query} <input_file>"
            echo ""
            echo "Commands:"
            echo "  detect <kg.json>           - Detect contradictions in knowledge graph"
            echo "  from-agent <output.json>   - Extract contradictions from agent output"
            echo "  query <contradiction.json> - Generate investigation query"
            ;;
    esac
fi
