# Commit Guide

## Format

```
type(scope): description
```

## Types

| Type | When | Release |
|------|------|---------|
| `feat` | New functionality | minor (1.x.0) |
| `fix` | Bug fix | patch (1.0.x) |
| `docs` | Documentation only | no release |
| `refactor` | Code change, no new feature or fix | no release |
| `chore` | Maintenance, deps, config | no release |
| `ci` | CI/CD changes | no release |
| `test` | Adding or updating tests | no release |

Add `!` after type for breaking changes: `feat!:` → major (x.0.0)

## Scopes

Use the area you're changing: `terraform`, `ansible`, `k3s`, `argocd`, `homepage`, etc.
Scope is optional but recommended.

## Examples

```bash
feat(terraform): add monitoring VM
fix(ansible): correct DNS resolver config
docs: update roadmap with phase 4
refactor: rename .yml files to .yaml
chore(deps): bump ingress-nginx to 4.12
ci: add release workflow
feat!: migrate from Traefik to ingress-nginx
```

## What happens on push

1. Push to `main` triggers semantic-release
2. Commits are analyzed — only `feat` and `fix` create a new release
3. CHANGELOG.md is updated automatically
4. A GitHub release + git tag is created

## Pre-commit hooks

Hooks run automatically on every commit:
- **Commit message** — must follow conventional commits format
- **Trailing whitespace** — auto-fixed
- **End of file** — ensures newline at end
- **YAML lint** — validates YAML files
- **Terraform fmt** — auto-formats .tf files
