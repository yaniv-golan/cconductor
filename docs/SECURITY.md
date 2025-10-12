# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |
| < 0.1   | :x:                |

## Installation Security

### Verified Installation

Always verify checksums when installing in production:

```bash
# Download installer and checksum
curl -LO https://github.com/yaniv-golan/cconductor/releases/latest/download/install.sh
curl -LO https://github.com/yaniv-golan/cconductor/releases/latest/download/install.sh.sha256

# Verify integrity
sha256sum -c install.sh.sha256

# Install
bash install.sh
```

### Release Artifacts

All release artifacts include SHA256 checksums:

- `install.sh.sha256` - Installer checksum
- `cconductor.sha256` - Main script checksum
- `cconductor-v{version}.tar.gz.sha256` - Archive checksum
- `CHECKSUMS.txt` - Combined checksums file

Verify any downloaded artifact before use:

```bash
sha256sum -c <file>.sha256
```

## Update Security

CConductor's update checker:

- ✅ Only queries GitHub API over HTTPS
- ✅ Never sends telemetry or usage data
- ✅ Never collects user information
- ✅ Can be disabled via configuration
- ✅ Non-blocking and fails silently when offline

To disable update checks:

```json
{
  "update_settings": {
    "check_for_updates": false
  }
}
```

## Reporting a Vulnerability

**Email:** <yaniv@golan.name>

**Response Time:** We aim to respond within 48 hours.

**What to Include:**

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

**Disclosure Policy:**

- We will acknowledge your email within 48 hours
- We will provide a fix timeline within 7 days
- We will credit you in the security advisory (unless you prefer to remain anonymous)

## Security Best Practices

### For Users

1. **Verify Checksums** - Always verify checksums for production installations
2. **Review Release Notes** - Check what changed before updating
3. **Test Updates** - Test in non-production environment first
4. **Pin Versions** - Use specific version tags in CI/CD pipelines
5. **Use Security Profiles** - Configure appropriate security level in `config/security-config.json`
6. **Keep Updated** - Apply security updates promptly

### For Developers

1. **Code Review** - All changes reviewed before merge
2. **ShellCheck** - All scripts pass ShellCheck linting
3. **Dependencies** - Minimal external dependencies (jq, curl, bash)
4. **No Secrets** - Never commit API keys or secrets
5. **Least Privilege** - Scripts run with minimal necessary permissions

## Known Limitations

1. **Installer requires curl** - Users must trust curl downloads over HTTPS
2. **No GPG signing** - Release artifacts are not GPG signed (planned for v1.0)
3. **Bash required** - Vulnerabilities in bash affect CConductor
4. **Git clone option** - Cloning from git bypasses checksum verification

## Security Features

### Current Features

- ✅ SHA256 checksums for all releases
- ✅ HTTPS-only downloads
- ✅ Configurable security profiles
- ✅ No telemetry or tracking
- ✅ Offline-capable operation
- ✅ Minimal dependencies

### Planned (v1.0+)

- ⏳ GPG signing of releases
- ⏳ SBOM (Software Bill of Materials) generation
- ⏳ Automated vulnerability scanning
- ⏳ Supply chain security attestation
- ⏳ Code signing for macOS/Windows

## Security Audits

Last audit: Not yet conducted  

## Contact

**Security Issues:** <yaniv@golan.name>  
**General Questions:** <https://github.com/yaniv-golan/cconductor/discussions>

---

**Last Updated:** October 3, 2025
