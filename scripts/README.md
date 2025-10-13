# CConductor Scripts

Utility scripts for maintenance and development.

## Available Scripts

### Development Scripts

### `cleanup.sh`

Comprehensive cleanup script for CConductor development and testing.

**Usage:**

```bash
./scripts/cleanup.sh
```

**What it cleans:**

1. **Processes**
   - CConductor processes
   - Claude CLI processes
   - HTTP server processes (from dashboard)

2. **Research Sessions**
   - All `research-sessions/session_*` directories
   - `.latest` symlink
   - Interactive confirmation before deletion

3. **Temporary Files**
   - `/tmp/test-agents` directory
   - `.backup`, `.bak`, `~` files
   - Log files (with confirmation)

**Interactive:**

- Asks for confirmation before deleting sessions and logs
- Shows summary of what was cleaned
- Safe to run anytime

**Example Output:**

```
╔═══════════════════════════════════════════════════════════╗
║            CCONDUCTOR - CLEANUP SCRIPT                         ║
╚═══════════════════════════════════════════════════════════╝

→ Checking for running processes...
  → Killing HTTP server processes: 1234
  ✓ Killed 1 process(es)

→ Cleaning research sessions...
  → Found 3 session(s) (Total: 2.5M)
  → Delete all sessions? [y/N] y
  ✓ Deleted 3 session(s)

→ Cleaning temporary files...
  ✓ Removed .latest symlink

╔═══════════════════════════════════════════════════════════╗
║                   CLEANUP SUMMARY                         ║
╚═══════════════════════════════════════════════════════════╝

  Sessions remaining: 0
  Processes running: 0

  ✓ System is clean!

✓ Cleanup complete
```

---

### `code-health.sh`

Reports code quality metrics (function counts, LOC, TODOs, manual locking usage).

**Usage:**

```bash
./scripts/code-health.sh
```

---

### `check-locking.sh`

Checks for manual `lock_acquire`/`lock_release` usage vs atomic operations.

**Usage:**

```bash
./scripts/check-locking.sh
```

Helps track refactoring progress toward using `atomic_json_update` consistently.

---

### Release Management Scripts

### `generate-checksums.sh`

Generates SHA256 checksums for distribution files (used in releases).

**Usage:**

```bash
./scripts/generate-checksums.sh [version]
```

**Note:** Critical for secure self-updates (Issue #4 fix).

---

### `verify-version.sh`

Validates VERSION file matches git tag with semver format validation.

**Usage:**

```bash
./scripts/verify-version.sh v0.1.0
```

**Note:** Recently improved to validate semver format (Issue #27 fix).

---

## Adding New Scripts

When adding new scripts:

1. Place in `scripts/` directory
2. Make executable: `chmod +x scripts/your-script.sh`
3. Add shebang: `#!/bin/bash`
4. Document in this README
5. Use `set -e` for safety
6. Include usage instructions in script comments
