#!/usr/bin/env bash
# Safe Calculation Wrapper
# Provides accurate math calculations for LLM agents
# LLMs are unreliable at arithmetic - use this instead!

set -euo pipefail

# Safe calculation with input validation
safe_calculate() {
    local expression="$1"
    
    # Check bc availability (required for this specialized math tool)
    if ! command -v bc &> /dev/null; then
        jq -n \
            --arg err "bc not installed. This Calculate tool requires bc for precise mathematical operations. Install: 'brew install bc' (macOS) or 'apt install bc' (Linux)" \
            '{result: null, error: $err}' >&2
        return 1
    fi

    # Input validation - only allow safe characters
    if ! echo "$expression" | grep -qE '^[0-9+*/.()eE, 	-]+$'; then
        echo '{"error": "Invalid expression - only numbers and basic operators allowed", "result": null}' >&2
        return 1
    fi

    # Evaluate using bc -l (no external interpreters)
    # Use scale for precision but return as a JSON number
    local calc_out
    if ! calc_out=$(echo "scale=12; ($expression)" | bc -l 2>/dev/null); then
        jq -n --arg err "Invalid expression or calculation error" '{result: null, error: $err}' >&2
        return 1
    fi

    # Normalize + convert to number via jq (handles scientific/decimal)
    jq -n --arg r "$calc_out" '{result: ($r|tonumber), error: null}'
}

# Calculate percentage
calculate_percentage() {
    local part="$1"
    local whole="$2"

    # Validate inputs are numbers
    if ! [[ "$part" =~ ^[0-9.eE+-]+$ ]] || ! [[ "$whole" =~ ^[0-9.eE+-]+$ ]]; then
        echo '{"error": "Invalid input - arguments must be numbers", "percentage": null}' >&2
        return 1
    fi

    # Compute with awk (handles floating point and rounding)
    local out
    if ! out=$(awk -v p="$part" -v w="$whole" 'BEGIN{ if (w==0) exit 2; printf "%.2f", (p/w)*100 }'); then
        jq -n --arg err "Division by zero" '{percentage: null, error: $err}' >&2
        return 1
    fi
    jq -n --arg v "$out" '{percentage: ($v|tonumber), error: null}'
}

# Calculate growth rate
calculate_growth_rate() {
    local old_value="$1"
    local new_value="$2"

    # Validate inputs are numbers
    if ! [[ "$old_value" =~ ^[0-9.eE+-]+$ ]] || ! [[ "$new_value" =~ ^[0-9.eE+-]+$ ]]; then
        echo '{"error": "Invalid input - arguments must be numbers", "growth_rate": null}' >&2
        return 1
    fi

    # Compute with awk
    local output
    if ! output=$(awk -v o="$old_value" -v n="$new_value" 'BEGIN{ if (o==0) exit 2; printf "%.2f %.2f", ((n-o)/o)*100, (n/o) }'); then
        jq -n --arg err "Old value is zero" '{growth_rate: null, multiplier: null, error: $err}' >&2
        return 1
    fi
    
    local gr mult
    read -r gr mult <<< "$output"
    jq -n --arg gr "$gr" --arg m "$mult" '{growth_rate: ($gr|tonumber), multiplier: ($m|tonumber), error: null}'
}

# Calculate CAGR (Compound Annual Growth Rate)
calculate_cagr() {
    local start="$1"
    local end="$2"
    local years="$3"

    # Validate inputs are numbers
    if ! [[ "$start" =~ ^[0-9.eE+-]+$ ]] || ! [[ "$end" =~ ^[0-9.eE+-]+$ ]] || ! [[ "$years" =~ ^[0-9.eE+-]+$ ]]; then
        echo '{"error": "Invalid input - arguments must be numbers", "cagr": null}' >&2
        return 1
    fi

    # Validate domain and compute with awk: pow(x, y) = exp(log(x)*y)
    if awk -v s="$start" -v e="$end" -v y="$years" 'BEGIN{ exit ! (s>0 && e>0 && y>0) }'; then
        :
    else
        jq -n --arg err "Start/end/years must be positive" '{cagr: null, error: $err}' >&2
        return 1
    fi

    local cagr
    if ! cagr=$(awk -v s="$start" -v e="$end" -v y="$years" 'BEGIN{ c = (exp(log(e/s)/y)-1)*100; printf "%.2f", c }'); then
        jq -n --arg err "Calculation error" '{cagr: null, error: $err}' >&2
        return 1
    fi
    jq -n --arg v "$cagr" '{cagr: ($v|tonumber), error: null}'
}

# Export functions
export -f safe_calculate
export -f calculate_percentage
export -f calculate_growth_rate
export -f calculate_cagr

# CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        calc)
            safe_calculate "$2"
            ;;
        percentage|pct)
            calculate_percentage "$2" "$3"
            ;;
        growth)
            calculate_growth_rate "$2" "$3"
            ;;
        cagr)
            calculate_cagr "$2" "$3" "$4"
            ;;
        *)
            cat <<EOF
Safe Calculation Wrapper for LLM Agents
========================================

LLMs are unreliable at arithmetic. Use this for accurate calculations.

Usage: $0 <command> <args>

Commands:
  calc <expression>              - Safe math evaluation
  percentage <part> <whole>      - Calculate percentage
  growth <old> <new>             - Calculate growth rate
  cagr <start> <end> <years>     - Calculate CAGR

Examples:
  # TAM calculation (500M people × \$50)
  $0 calc "500000000 * 50"
  # Output: {"result": 25000000000.0, "error": null}

  # Market share (5M out of 50M)
  $0 percentage 5000000 50000000
  # Output: {"percentage": 10.0, "error": null}

  # Revenue growth (10M → 15M)
  $0 growth 10000000 15000000
  # Output: {"growth_rate": 50.0, "multiplier": 1.5, "error": null}

  # CAGR over 5 years (1M → 10M)
  $0 cagr 1000000 10000000 5
  # Output: {"cagr": 58.49, "error": null}

Safety Features:
  • Input validation (only numbers and operators)
  • Pure Bash + bc/awk math (no external interpreters)
  • JSON output (structured and parsable)
  • Error handling (graceful failures)
EOF
            ;;
    esac
fi