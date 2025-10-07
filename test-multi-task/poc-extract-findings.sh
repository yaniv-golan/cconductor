#!/usr/bin/env bash
# POC: Extract findings from file-based agent output

set -euo pipefail

agent_output="$1"
session_dir="$2"

echo "=== POC: File-Based Findings Extraction ==="
echo ""

# Check if agent used file-based output
if jq -e '.result.findings_files' "$agent_output" >/dev/null 2>&1; then
    echo "✓ Detected file-based output"
    echo ""
    
    # Extract file paths
    findings_files=$(jq -r '.result.findings_files[]' "$agent_output")
    
    # Initialize findings array
    new_findings="[]"
    
    # Read each finding file
    count=0
    for finding_file in $findings_files; do
        full_path="$session_dir/$finding_file"
        
        if [ -f "$full_path" ]; then
            echo "  ✓ Reading: $finding_file"
            finding=$(cat "$full_path")
            
            # Validate JSON
            if echo "$finding" | jq empty 2>/dev/null; then
                # Add to findings array
                new_findings=$(echo "$new_findings" | jq --argjson f "$finding" '. += [$f]')
                count=$((count + 1))
            else
                echo "  ✗ Invalid JSON in $finding_file"
            fi
        else
            echo "  ✗ File not found: $full_path"
        fi
    done
    
    echo ""
    echo "=== Results ==="
    echo "Files processed: $count"
    echo "Findings extracted: $(echo "$new_findings" | jq 'length')"
    echo ""
    echo "=== Sample Finding ==="
    echo "$new_findings" | jq '.[0]'
    echo ""
    echo "=== All Task IDs ==="
    echo "$new_findings" | jq -r '.[].task_id'
    echo ""
    
    # Token comparison
    echo "=== Token Efficiency ==="
    agent_response_size=$(jq -r '.result' "$agent_output" | wc -c | tr -d ' ')
    findings_total_size=$(echo "$new_findings" | wc -c | tr -d ' ')
    echo "Agent response: ~$agent_response_size bytes (~$((agent_response_size / 4)) tokens)"
    echo "Total findings: ~$findings_total_size bytes (~$((findings_total_size / 4)) tokens)"
    echo "If findings were inline: Would be ~$((findings_total_size / 4)) tokens in agent response"
    echo ""
    
else
    echo "✗ Not file-based output (legacy inline format)"
    echo ""
    echo "Agent would need to return:"
    jq '.result' "$agent_output"
fi
