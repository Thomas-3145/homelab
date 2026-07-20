#!/usr/bin/env bash
# Create a DNS-only A record in the 3145.blog zone pointing at the k3s ingress VIP.
# Usage: cf-add-record.sh <name> [ip]
set -euo pipefail

NAME="${1:?usage: cf-add-record.sh <name> [ip]}"
IP="${2:-192.168.10.200}"
ZONE="2124f1907ac26d9add715cea222cf2ab"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CF_TOKEN="$(sops -d "$REPO/kubernetes/infrastructure/cert-manager/cloudflare-api-token.sops.yaml" \
  | grep -oP '(?<=api-token: ).*' | tr -d "\"' ")"

curl -s -X POST \
  -H "Authorization: Bearer $CF_TOKEN" \
  -H "Content-Type: application/json" \
  --data "{\"type\":\"A\",\"name\":\"$NAME\",\"content\":\"$IP\",\"ttl\":1,\"proxied\":false}" \
  "https://api.cloudflare.com/client/v4/zones/$ZONE/dns_records" \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
if d.get('success'):
    r = d['result']
    print(f\"OK: {r['name']} {r['type']} -> {r['content']} (proxied={r['proxied']})\")
else:
    print('FAILED:', json.dumps(d.get('errors'), indent=2))
    sys.exit(1)
"
