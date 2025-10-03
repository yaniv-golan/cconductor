# Contributing to Delve

Thank you for your interest in contributing to Delve! This document provides guidelines and information for contributors.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
- [Testing](#testing)
- [Submitting Changes](#submitting-changes)
- [Documentation](#documentation)

---

## Code of Conduct

This project adheres to a code of conduct that all contributors are expected to follow:

- **Be respectful** and inclusive in all interactions
- **Be collaborative** and open to feedback
- **Be constructive** in criticism and suggestions
- **Focus on what is best** for the project and community

---

## How Can I Contribute?

### Reporting Bugs

Before creating a bug report:

1. **Check existing issues** to avoid duplicates
2. **Use the latest version** to see if the bug persists
3. **Gather information** about your environment

When filing a bug report, include:

- **Clear title** describing the issue
- **Steps to reproduce** the problem
- **Expected vs. actual behavior**
- **Environment details** (OS, bash version, dependencies)
- **Error messages** and relevant logs
- **Minimal test case** if possible

### Suggesting Enhancements

Enhancement suggestions are welcome! Include:

- **Clear description** of the enhancement
- **Use case** explaining why it's useful
- **Examples** of how it would work
- **Alternatives** you've considered

### Contributing Code

Areas where contributions are especially welcome:

- Bug fixes and error handling improvements
- Performance optimizations
- Cross-platform compatibility enhancements
- New output formats (HTML, JSON)
- Enhanced PDF extraction
- Additional research agents or modes
- Test coverage improvements
- Documentation improvements

---

## Development Setup

### Prerequisites

```bash
# Required
bash --version  # 4.0 or higher
jq --version
curl --version

# Optional but recommended
python3 --version
```

### Getting Started

```bash
# Clone the repository
git clone https://github.com/yaniv-golan/delve.git
cd delve

# Run setup (automatic on first use)
./delve --version

# Run tests
./tests/run-all-tests.sh
```

---

## Coding Standards

### Bash Style Guide

**General Principles:**

- Use `#!/bin/bash` shebang
- Include `set -euo pipefail` for safety
- Use meaningful variable names
- Add comments for complex logic
- Keep functions focused and small

**Naming Conventions:**

```bash
# Variables: lowercase with underscores
local my_variable="value"

# Constants: uppercase with underscores
readonly MAX_RETRIES=3

# Functions: lowercase with underscores
function do_something() {
    ...
}
```

**Error Handling:**

```bash
# Always check command success
if ! some_command; then
    echo "Error: command failed" >&2
    return 1
fi

# Use || for simple error handling
mkdir -p "$dir" || { echo "Failed to create directory" >&2; exit 1; }
```

**Quoting:**

```bash
# Always quote variables
local file="$1"
echo "Processing: $file"

# Use arrays for multiple values
local files=("$@")
```

### JSON Configuration

- Use `.default.json` suffix for templates
- Validate JSON syntax before committing
- Document all configuration options
- Use descriptive keys

### Documentation

- Keep README.md concise and user-focused
- Use docs/ for detailed guides
- Include examples in documentation
- Update CHANGELOG.md for all changes

---

## Testing

### Running Tests

```bash
# Run all tests
./tests/run-all-tests.sh

# Run specific test
./tests/test-simple-query.sh
```

### Writing Tests

- Add tests for new features
- Test error conditions
- Verify cross-platform compatibility
- Use descriptive test names

**Test Structure:**

```bash
#!/bin/bash
# Test: description of what's being tested

set -euo pipefail

# Setup
source "$(dirname "$0")/../src/shared-state.sh"

# Test case
test_function_name() {
    # Arrange
    local input="test input"
    
    # Act
    local result=$(function_to_test "$input")
    
    # Assert
    if [[ "$result" != "expected output" ]]; then
        echo "FAIL: Expected 'expected output', got '$result'"
        return 1
    fi
    
    echo "PASS"
    return 0
}

# Run test
test_function_name
```

---

## Submitting Changes

### Pull Request Process

1. **Create a branch** from `main`

   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
   - Follow coding standards
   - Add tests if applicable
   - Update documentation

3. **Test thoroughly**

   ```bash
   ./tests/run-all-tests.sh
   ```

4. **Commit with clear messages**

   ```bash
   git commit -m "Add feature: clear description"
   ```

5. **Push and create PR**

   ```bash
   git push origin feature/your-feature-name
   ```

### Commit Message Guidelines

Use clear, descriptive commit messages:

```
Type: Brief summary (50 chars or less)

More detailed explanation if needed. Wrap at 72 characters.
Explain what and why, not how.

- Bullet points are okay
- Use present tense ("Add feature" not "Added feature")
- Reference issues: "Fixes #123"
```

**Types:**

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style/formatting
- `refactor`: Code refactoring
- `test`: Test additions/changes
- `chore`: Maintenance tasks

### Pull Request Guidelines

- **One feature/fix per PR** - Keep changes focused
- **Update CHANGELOG.md** - Document your changes
- **Add tests** - If applicable
- **Update documentation** - If behavior changes
- **Ensure CI passes** - All tests must pass
- **Respond to feedback** - Address review comments

---

## Documentation

### Documentation Structure

```
docs/
├── USER_GUIDE.md           # Comprehensive user guide
├── QUICK_REFERENCE.md      # Command cheat sheet
├── SECURITY_GUIDE.md       # Security configuration
├── CITATIONS_GUIDE.md      # Using citations
├── CUSTOM_KNOWLEDGE.md     # Adding domain knowledge
├── TROUBLESHOOTING.md      # Common problems
└── ...
```

### Documentation Standards

- **User-focused** - Write for the end user
- **Examples** - Include practical examples
- **Up-to-date** - Keep in sync with code
- **Clear structure** - Use headings and sections
- **Searchable** - Use descriptive titles

### Updating Documentation

When making changes that affect users:

1. Update relevant guide in `docs/`
2. Update README.md if necessary
3. Add entry to CHANGELOG.md
4. Update version in VERSION file (for releases)

---

## Questions?

If you have questions about contributing:

- **Check documentation** in `docs/`
- **Search existing issues** on GitHub
- **Ask in discussions** on GitHub
- **Open an issue** with the "question" label

---

## Recognition

Contributors will be:

- Listed in CONTRIBUTORS.md (coming soon)
- Credited in release notes
- Acknowledged in the project

Thank you for helping make Delve better! 🔍
