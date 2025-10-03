#!/bin/bash
# Safe Calculation Wrapper
# Provides accurate math calculations for LLM agents
# LLMs are unreliable at arithmetic - use this instead!

set -euo pipefail

# Safe calculation with input validation
safe_calculate() {
    local expression="$1"

    # Input validation - only allow safe characters
    if ! echo "$expression" | grep -qE '^[0-9+*/.()eE, 	-]+$'; then
        echo '{"error": "Invalid expression - only numbers and basic operators allowed", "result": null}' >&2
        return 1
    fi

    # Use Python with restricted builtins for safety
    python3 -c "
import math
import json
import sys

safe_builtins = {'abs': abs, 'round': round, 'min': min, 'max': max, 'pow': pow, 'int': int, 'float': float}
safe_math = {'sqrt': math.sqrt, 'log': math.log, 'exp': math.exp, 'pi': math.pi, 'e': math.e}

try:
    result = eval('$expression', {'__builtins__': safe_builtins, 'math': type('math', (), safe_math)})
    print(json.dumps({'result': result, 'error': None}))
except Exception as e:
    print(json.dumps({'result': None, 'error': str(e)}), file=sys.stderr)
    sys.exit(1)
"
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

    python3 -c "
import json
import sys
try:
    part, whole = float('$part'), float('$whole')
    if whole == 0:
        print(json.dumps({'percentage': None, 'error': 'Division by zero'}), file=sys.stderr)
        sys.exit(1)
    percentage = round((part / whole) * 100, 2)
    print(json.dumps({'percentage': percentage, 'error': None}))
except Exception as e:
    print(json.dumps({'percentage': None, 'error': str(e)}), file=sys.stderr)
    sys.exit(1)
"
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

    python3 -c "
import json
import sys
try:
    old, new = float('$old_value'), float('$new_value')
    if old == 0:
        print(json.dumps({'growth_rate': None, 'multiplier': None, 'error': 'Old value is zero'}), file=sys.stderr)
        sys.exit(1)
    growth_rate = round(((new - old) / old) * 100, 2)
    multiplier = round(new / old, 2)
    print(json.dumps({'growth_rate': growth_rate, 'multiplier': multiplier, 'error': None}))
except Exception as e:
    print(json.dumps({'growth_rate': None, 'multiplier': None, 'error': str(e)}), file=sys.stderr)
    sys.exit(1)
"
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

    python3 -c "
import json
import sys
try:
    start, end, years = float('$start'), float('$end'), float('$years')
    if start <= 0 or end <= 0:
        print(json.dumps({'cagr': None, 'error': 'Start and end values must be positive'}), file=sys.stderr)
        sys.exit(1)
    if years <= 0:
        print(json.dumps({'cagr': None, 'error': 'Years must be positive'}), file=sys.stderr)
        sys.exit(1)
    cagr = (((end / start) ** (1 / years)) - 1) * 100
    print(json.dumps({'cagr': round(cagr, 2), 'error': None}))
except Exception as e:
    print(json.dumps({'cagr': None, 'error': str(e)}), file=sys.stderr)
    sys.exit(1)
"
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
  • Restricted Python environment (no file I/O or system calls)
  • JSON output (structured and parsable)
  • Error handling (graceful failures)
EOF
            ;;
    esac
fi
