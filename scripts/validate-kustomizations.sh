#!/bin/bash
# Render every Kustomize overlay and schema-check the result.
# Usage: ./scripts/validate-kustomizations.sh
#
# Run by both the pre-commit hook and the CI lint workflow, so the two can
# never drift apart. Exits non-zero if any overlay fails to build or produces
# manifests that don't validate.
#
# KSOPS: if ksops is not on PATH, a stub is used that renders secrets as an
# empty list. Structure is what breaks a render — dangling patch targets, bad
# references — and that is still caught. With a real ksops plus the age key,
# secrets are decrypted and validated too.

set -uo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root" || exit 1

for tool in kustomize kubeconform; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: $tool not found on PATH" >&2
    echo "  kustomize:   https://kubectl.docs.kubernetes.io/installation/kustomize/" >&2
    echo "  kubeconform: https://github.com/yannh/kubeconform#installation" >&2
    exit 127
  fi
done

stub_dir=""
if ! command -v ksops >/dev/null 2>&1; then
  stub_dir=$(mktemp -d)
  trap 'rm -rf "$stub_dir"' EXIT
  cat > "$stub_dir/ksops" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
echo "apiVersion: config.kubernetes.io/v1"
echo "kind: ResourceList"
echo "items: []"
STUB
  chmod +x "$stub_dir/ksops"
  PATH="$stub_dir:$PATH"
  export PATH
fi

fail=0
while read -r kustomization; do
  dir=$(dirname "$kustomization")

  # Build and schema-check as two separate steps. Piping them together would
  # hide a failed build behind kubeconform, which exits 0 on empty input, and
  # would report a render error as an unhelpful YAML parse error.
  if ! rendered=$(kustomize build --enable-alpha-plugins --enable-exec "$dir" 2>&1); then
    echo "FAIL  $dir  (kustomize build)"
    printf '%s\n' "$rendered" | head -5 | sed 's/^/      /'
    fail=1
    continue
  fi

  if ! errors=$(printf '%s\n' "$rendered" \
                | kubeconform -strict -ignore-missing-schemas 2>&1); then
    echo "FAIL  $dir  (schema validation)"
    printf '%s\n' "$errors" | head -5 | sed 's/^/      /'
    fail=1
    continue
  fi

  echo "ok    $dir"
done < <(find kubernetes -name kustomization.yaml | sort)

exit $fail
