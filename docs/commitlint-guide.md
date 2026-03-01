# Commitlint + Husky Guide

## What It Does

**Husky** runs scripts (git hooks) automatically when you commit. **commitlint** validates that your commit message follows a standard format. Together they enforce consistent commit messages across a project.

The hook runs **before** the commit is created. If the message is wrong, the commit is rejected — no bad messages get through.

## The Format

```
type(scope): description
```

| Part | Required | Example |
|------|----------|---------|
| **type** | Yes | `feat`, `fix`, `docs`, `chore` |
| **scope** | No | `homepage`, `terraform`, `api` |
| **description** | Yes | Short, lowercase, imperative |

### Allowed Types

| Type | When to use |
|------|-------------|
| `feat` | New feature or functionality |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `style` | Formatting, whitespace (no logic change) |
| `refactor` | Code restructuring (no new feature, no bug fix) |
| `test` | Adding or updating tests |
| `chore` | Maintenance (deps, config, tooling) |
| `ci` | CI/CD pipeline changes |
| `build` | Build system changes |
| `perf` | Performance improvements |

### Examples

```bash
# Good
git commit -m "feat(homepage): add TLS support"
git commit -m "fix(ansible): correct inventory path"
git commit -m "docs: update README with setup instructions"
git commit -m "chore(deps): bump ingress-nginx to 4.9.0"

# Bad — these will be rejected
git commit -m "fixade grejer"           # no type
git commit -m "FEAT(homepage): stuff"   # type must be lowercase
git commit -m "feat: "                  # empty description
git commit -m "feat(homepage) missing colon"  # missing `: ` after scope
```

## Setup in a New Project

### Prerequisites

- Node.js installed (`node --version`)
- A git repository (`git init` if needed)

### Step-by-Step

```bash
# 1. Initialize package.json (skip if it already exists)
npm init -y

# 2. Install dependencies
npm install --save-dev @commitlint/cli @commitlint/config-conventional husky

# 3. Create commitlint config
echo "module.exports = { extends: ['@commitlint/config-conventional'] };" > commitlint.config.js

# 4. Initialize husky
npx husky init

# 5. Replace the pre-commit hook with a commit-msg hook
rm .husky/pre-commit
echo 'npx --no -- commitlint --edit $1' > .husky/commit-msg

# 6. Make sure node_modules is in .gitignore
echo "node_modules/" >> .gitignore
```

That's it. Every `git commit` now validates the message.

### Verify It Works

```bash
# Should fail
echo "bad message" | npx commitlint

# Should pass
echo "feat: add new feature" | npx commitlint
```

## Files Created

| File | Purpose |
|------|---------|
| `package.json` | Node.js project config, lists dependencies |
| `package-lock.json` | Locked dependency versions |
| `commitlint.config.js` | Tells commitlint which rules to use |
| `.husky/commit-msg` | Git hook that runs commitlint |
| `node_modules/` | Dependencies (gitignored) |

## After Cloning

When someone clones the repo (or you clone it on a new machine), they need to install dependencies for the hooks to work:

```bash
npm install
```

This installs commitlint, husky, and sets up the git hooks automatically.

## Bypassing (Emergency Only)

If you absolutely need to skip validation:

```bash
git commit -m "message" --no-verify
```

Use sparingly — the whole point is to enforce the format.

## Tips

- **Keep descriptions short** — under 72 characters
- **Use imperative mood** — "add feature" not "added feature"
- **Scope is optional** — `chore: update deps` is fine, `chore(deps): update` is better
- **Multi-line messages work** — only the first line is validated for format
