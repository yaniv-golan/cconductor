# WebFetch Policy Templates

This directory contains policy templates for WebFetch domain restrictions. These templates are **not active by default** - you must explicitly enable strict mode and copy a template to activate it.

## Available Templates

### `web-fetch-restricted.json`

**Use case**: Compliance, security-sensitive environments, or when you need strict domain controls.

**Restrictions**:
- Only allows: `*.gov`, `*.edu`, `wikipedia.org`, `github.com`, `stackoverflow.com`
- Blocks: `canva.com`, `figma.com`, `medium.com`, `pinterest.com`

## How to Activate a Policy

1. **Copy the template** to the main config directory:
   ```bash
   cp config/policies/web-fetch-restricted.json config/web-fetch-limits.json
   ```

2. **Enable strict mode** using one of these methods:
   - Environment variable: `export CCONDUCTOR_WEB_FETCH_STRICT_MODE=1`
   - CLI flag: `./cconductor --strict-web-fetch "your research question"`
   - Per-session: Set the env var before running a mission

3. **Verify activation**:
   - The system will automatically load `config/web-fetch-limits.json` when strict mode is enabled
   - Check logs if WebFetch attempts are blocked unexpectedly

## Default Behavior

By default, WebFetch operates in **permissive mode** (strict mode off):
- All domains are allowed (except those in `blocked_domains`)
- No domain allowlist restrictions
- Optimized for "useful out of the box" experience

## Custom Policies

You can create custom policies by:
1. Copying a template: `cp config/policies/web-fetch-restricted.json config/web-fetch-limits.json`
2. Editing `allowed_domains` and `blocked_domains` arrays
3. Enabling strict mode as described above

## Policy File Structure

```json
{
  "max_uses_per_turn": 2,
  "max_content_tokens": 60000,
  "allowed_domains": ["*.gov", "*.edu", "..."],
  "blocked_domains": ["canva.com", "..."]
}
```

- `allowed_domains`: Array of domain patterns (empty = allow all when strict mode is off)
- `blocked_domains`: Array of domains to always block (applies regardless of strict mode)
- `max_uses_per_turn`: Maximum WebFetch calls per agent turn
- `max_content_tokens`: Maximum content size limit

## See Also

- [Troubleshooting Guide](../docs/TROUBLESHOOTING.md) - WebFetch policy issues
- [User Guide](../docs/USER_GUIDE.md) - Security settings section
- [Configuration Reference](../docs/CONFIGURATION_REFERENCE.md) - Environment variables


