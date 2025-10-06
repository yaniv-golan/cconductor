#!/usr/bin/env bash
# HTML Output Formatter
# Converts research JSON to standalone HTML report

set -euo pipefail

RESEARCH_FILE="$1"

# Convert markdown to HTML using the markdown formatter + pandoc
# Or implement custom HTML generation

# For now, just convert markdown output
MARKDOWN=$("$(dirname "$0")/markdown.sh" "$RESEARCH_FILE")

# Simple HTML wrapper (could use pandoc for better results)
cat <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Research Report</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; max-width: 900px; margin: 40px auto; padding: 20px; line-height: 1.6; }
        code { background: #f4f4f4; padding: 2px 6px; border-radius: 3px; }
        h1 { border-bottom: 3px solid #333; padding-bottom: 10px; }
        h2 { margin-top: 30px; border-bottom: 1px solid #ddd; padding-bottom: 5px; }
        blockquote { border-left: 4px solid #ddd; padding-left: 20px; color: #666; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px 12px; text-align: left; }
        th { background-color: #f4f4f4; font-weight: 600; }
    </style>
</head>
<body>
$MARKDOWN
</body>
</html>
EOF
