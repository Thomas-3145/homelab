#!/usr/bin/env bash
# morgonkoll.sh — one-shot morning health check for the homelab.
#
# Checks, in order:
#   - Proxmox hosts answer ping (pve1-3)
#   - UPS status via NUT on pve3 (charge, load, runtime)
#   - k3s nodes Ready
#   - pods that are not Running/Completed
#   - ArgoCD applications not Synced/Healthy
#   - most recent Velero backup phase and age
#
# Read-only. Exit 0 = all green, 1 = at least one issue (cron-friendly).
# Deliberately no `set -e`: one failing check must not abort the rest.
set -uo pipefail

RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
issues=0
ok()      { printf '  %b✔%b %s\n' "$GREEN" "$RESET" "$1"; }
warn()    { printf '  %b●%b %s\n' "$YELLOW" "$RESET" "$1"; }
bad()     { printf '  %b✘%b %s\n' "$RED" "$RESET" "$1"; issues=$((issues + 1)); }
section() { printf '\n%b%s%b\n' "$BOLD" "$1" "$RESET"; }

section "Proxmox"
for node in pve1:192.168.10.11 pve2:192.168.10.12 pve3:192.168.10.13; do
  name=${node%%:*} ip=${node##*:}
  if ping -c1 -W1 "$ip" >/dev/null 2>&1; then
    ok "$name ($ip)"
  else
    bad "$name ($ip) does not answer ping"
  fi
done

section "UPS (NUT on pve3)"
if ups=$(timeout 5 ssh -o BatchMode=yes -o ConnectTimeout=3 pve3 'upsc apc 2>/dev/null') && [[ -n "$ups" ]]; then
  status=$(awk -F': ' '$1 == "ups.status"      {print $2}' <<<"$ups")
  charge=$(awk -F': ' '$1 == "battery.charge"  {print $2}' <<<"$ups")
  runtime=$(awk -F': ' '$1 == "battery.runtime" {print $2}' <<<"$ups")
  load=$(awk -F': '   '$1 == "ups.load"        {print $2}' <<<"$ups")
  line="status=${status:-?} charge=${charge:-?}% load=${load:-?}% runtime=$(( ${runtime:-0} / 60 ))min"
  # OL = on line power; anything else (OB, LB...) means running on battery
  if [[ "$status" == OL* ]]; then ok "$line"; else bad "$line — on battery?"; fi
else
  warn "could not read UPS over SSH (skipped)"
fi

section "k3s nodes"
if nodes=$(kubectl get nodes --no-headers 2>/dev/null) && [[ -n "$nodes" ]]; then
  while read -r name status _; do
    case "$status" in
      Ready)   ok "$name" ;;
      Ready,*) warn "$name is $status" ;;
      *)       bad "$name is $status" ;;
    esac
  done <<<"$nodes"
else
  bad "kubectl cannot reach the cluster"
fi

section "Pods"
if pods=$(kubectl get pods -A --no-headers 2>/dev/null); then
  badpods=$(awk '$4 != "Running" && $4 != "Completed"' <<<"$pods")
  if [[ -n "$badpods" ]]; then
    while read -r ns name ready status _; do
      bad "$ns/$name is $status ($ready)"
    done <<<"$badpods"
  else
    ok "all $(wc -l <<<"$pods") pods Running/Completed"
  fi
  # Restarts in the last 24h show up as "N (XmYs ago)" / "N (XhYm ago)"
  recent=$(awk '$4 == "Running" && $5 + 0 > 0 && $6 ~ /^\([0-9]+[mh]/' <<<"$pods")
  if [[ -n "$recent" ]]; then
    while read -r ns name _ _ n when _; do
      warn "$ns/$name restarted ${n}x, last $when ago)"
    done <<<"$recent"
  fi
else
  bad "could not list pods"
fi

section "ArgoCD applications"
if apps=$(kubectl get applications.argoproj.io -n argocd --no-headers \
    -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null) \
    && [[ -n "$apps" ]]; then
  badapps=$(awk '$2 != "Synced" || $3 != "Healthy"' <<<"$apps")
  if [[ -n "$badapps" ]]; then
    while read -r name sync health; do
      bad "$name: sync=$sync health=$health (try: argof)"
    done <<<"$badapps"
  else
    ok "all $(wc -l <<<"$apps") applications Synced + Healthy"
  fi
else
  bad "could not list ArgoCD applications"
fi

section "Velero"
if last=$(kubectl get backups.velero.io -n velero --sort-by=.metadata.creationTimestamp --no-headers \
    -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,START:.metadata.creationTimestamp 2>/dev/null | tail -1) \
    && [[ -n "$last" ]]; then
  read -r name phase start <<<"$last"
  age_h=$(( ( $(date +%s) - $(date -d "$start" +%s) ) / 3600 ))
  case "$phase" in
    Completed)       ok "$name (Completed, ${age_h}h ago)" ;;
    PartiallyFailed) bad "$name (PartiallyFailed, ${age_h}h ago) — velero backup logs $name" ;;
    *)               bad "$name ($phase, ${age_h}h ago)" ;;
  esac
  (( age_h > 26 )) && bad "latest backup is ${age_h}h old — schedule not running?"
else
  warn "no Velero backups found (or CRD missing)"
fi

echo
if (( issues == 0 )); then
  printf '%bAllt grönt ✔%b\n' "$GREEN" "$RESET"
else
  printf '%b%d problem hittade%b\n' "$RED" "$issues" "$RESET"
fi
exit $(( issues > 0 ))
