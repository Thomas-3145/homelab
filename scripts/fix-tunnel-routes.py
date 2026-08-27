#!/usr/bin/env python3
"""
Steg 2: krymp Cloudflare Tunnel-ingressen till den yta som faktiskt ska vara publik.

Läser nuvarande fjärrconfig, visar en diff, frågar om lov, och skriver sedan tillbaka.
Tokenen läses via lösenordsprompt och skrivs aldrig till disk.

Kör i en riktig terminalflik (behöver TTY):  python3 ~/fix-tunnel-routes.py
"""
import getpass
import json
import sys
import urllib.error
import urllib.request

TUNNEL_ID = "ce180050-7bb3-47bf-a4dd-a4ec5e56d592"
ORIGIN = "https://192.168.10.200"

# Den yta som ska vara internetnåbar. Allt annat åker ut.
KEEP = [
    "3145.blog",                 # Ghost-bloggen
    "argocd-webhook.3145.blog",  # GitHub-webhook, måste nås utifrån
    "ibindex.3145.blog",         # publik Streamlit-app
    "vault.3145.blog",           # Vaultwarden
    "auth.3145.blog",            # Authentik SSO
]

if not sys.stdin.isatty():
    sys.exit("Ingen TTY — kör i en vanlig terminalflik, inte via Claude Codes '!'-prefix.")

TOKEN = getpass.getpass("Cloudflare API-token: ").strip()
H = {"Authorization": "Bearer " + TOKEN, "Content-Type": "application/json"}


def cf(path, method="GET", body=None):
    req = urllib.request.Request(
        "https://api.cloudflare.com/client/v4" + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers=H, method=method)
    try:
        return json.loads(urllib.request.urlopen(req, timeout=30).read())
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path} -> {e.code}\n{e.read().decode()[:500]}")


v = cf("/user/tokens/verify")
print(f"✓ token: {v['result'].get('status')}")

# /accounts kräver 'Account Settings: Read' för att kunna lista. Vi har bara
# Tunnel:Edit + DNS:Edit, så konto-ID:t hämtas via zonen i stället.
zones = cf("/zones?name=3145.blog")["result"]
if not zones:
    sys.exit("Tokenen ser inte zonen 3145.blog — saknar den 'Zone -> DNS -> Edit'?")
acct = zones[0]["account"]["id"]
print(f"✓ konto: {zones[0]['account'].get('name')} ({acct[:8]}…)")

cfg = cf(f"/accounts/{acct}/cfd_tunnel/{TUNNEL_ID}/configurations")["result"]
current = cfg["config"]["ingress"]
version = cfg.get("version")
print(f"✓ nuvarande fjärrconfig: version {version}, {len(current)} regler\n")

print("NUVARANDE:")
for rule in current:
    host = rule.get("hostname")
    print(f"   {'(catch-all)' if not host else host:<28} -> {rule.get('service')}")

new_ingress = [
    {"hostname": h, "service": ORIGIN, "originRequest": {"noTLSVerify": True}}
    for h in KEEP
] + [{"service": "http_status:404"}]

removed = sorted({r.get("hostname") for r in current if r.get("hostname")} - set(KEEP))
print("\nTAS BORT:")
for h in removed:
    print(f"   {h}")
if not removed:
    print("   (inget — configen är redan krympt)")
    sys.exit(0)

print("\nEFTERÅT:")
for h in KEEP:
    print(f"   {h}")
print("   (catch-all)              -> http_status:404")

print("\nDe borttagna namnen slutar fungera via tunneln. De med A-post mot")
print("192.168.10.200 nås fortfarande på LAN/Tailscale — det är avsikten.")
if input("\nSkriv JA för att skriva: ").strip() != "JA":
    sys.exit("Avbrutet, inget ändrat.")

out = cf(f"/accounts/{acct}/cfd_tunnel/{TUNNEL_ID}/configurations", "PUT",
         {"config": {"ingress": new_ingress, "warp-routing": {"enabled": False}}})
print("\n✓ skrivet — ny version:", out["result"].get("version"))
print("\nVerifiera om ~30 s:")
print("  curl -sI https://home.3145.blog | head -1     # ska inte längre nå Homepage")
print("  curl -sI https://vault.3145.blog | head -1    # ska fortsatt ge 200")
print("  ssh router 'docker logs --tail 5 cloudflared'  # ska visa en ny config-version")
