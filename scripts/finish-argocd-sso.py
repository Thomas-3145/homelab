#!/usr/bin/env python3
"""
Sista steget för ArgoCD ↔ Authentik SSO.

Hämtar OAuth2-providerns client_secret ur Authentik, skriver in det i argocd-secret
och startar om argocd-server. Hemligheten skrivs aldrig ut och lämnar aldrig maskinen.

Kör:  python3 ~/finish-argocd-sso.py
"""
import base64
import http.client
import json
import ssl
import subprocess
import sys

import yaml

REPO = "/home/thomas/dev/3145/homelab"
SOPS_FILE = "kubernetes/infrastructure/authentik/authentik-secrets.sops.yaml"
INGRESS = "192.168.10.200"

# 1. Authentik-token ur SOPS
r = subprocess.run(["sops", "-d", SOPS_FILE], cwd=REPO,
                   capture_output=True, text=True, timeout=60)
if r.returncode:
    sys.exit("sops misslyckades: " + r.stderr.strip()[:300])
token = yaml.safe_load(r.stdout)["stringData"]["AUTHENTIK_BOOTSTRAP_TOKEN"]
print("✓ Authentik-token dekrypterad")

# 2. client_secret från providern (via intern ingress — Cloudflare blockerar /api/)
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
conn = http.client.HTTPSConnection(INGRESS, 443, context=ctx, timeout=30)
conn.request("GET", "/api/v3/providers/oauth2/1/", headers={
    "Host": "auth.3145.blog",
    "Authorization": "Bearer " + token,
    "Accept": "application/json",
})
resp = conn.getresponse()
if resp.status != 200:
    sys.exit(f"Authentik-API svarade {resp.status}: {resp.read().decode()[:300]}")
provider = json.loads(resp.read())
client_secret = provider["client_secret"]
print(f"✓ client_secret hämtat för provider '{provider['name']}' ({len(client_secret)} tecken)")

if provider["client_id"] != "4cBuEH1U8sb9qsgA5auXFtZZ1vgA0sAeFgv4ADaL":
    sys.exit(f"AVBRYTER: client_id matchar inte det som står i argocd-cm "
             f"({provider['client_id']}). Uppdatera argocd-cm först.")

# 3. Skriv in i argocd-secret
patch = {"data": {"oidc.authentik.clientSecret":
                  base64.b64encode(client_secret.encode()).decode()}}
r = subprocess.run(["kubectl", "-n", "argocd", "patch", "secret", "argocd-secret",
                    "-p", json.dumps(patch)], capture_output=True, text=True, timeout=60)
if r.returncode:
    sys.exit("kubectl patch misslyckades: " + r.stderr.strip()[:300])
print("✓", r.stdout.strip())

# 4. Starta om argocd-server så den läser in OIDC-configen
for args in (["rollout", "restart", "deploy", "argocd-server"],
             ["rollout", "status", "deploy", "argocd-server", "--timeout=150s"]):
    r = subprocess.run(["kubectl", "-n", "argocd", *args],
                       capture_output=True, text=True, timeout=200)
    print("✓", (r.stdout.strip().splitlines() or [""])[-1])
    if r.returncode:
        sys.exit(r.stderr.strip()[:300])

print()
print("Klart. Testa så här:")
print("  1. Öppna https://argocd.3145.blog i ett privat fönster")
print("  2. Det ska nu finnas en 'LOG IN VIA AUTHENTIK'-knapp bredvid vanliga inloggningen")
print("  3. Logga in som akadmin — du hamnar i ArgoCD utan admin-rättigheter ännu")
print()
print("För admin-rättigheter via SSO: lägg din Authentik-användare i gruppen")
print("'ArgoCD Admins' (Directory -> Groups i Authentik-UI:t).")
print("Det lokala admin-kontot fungerar oförändrat som break-glass.")
