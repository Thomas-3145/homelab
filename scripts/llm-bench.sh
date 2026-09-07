#!/bin/bash
# Benchmark a GGUF model on the ai-lab LXC (201, pve2) and record what it cost
# thermally. Runs from the workstation; drives pve2 over SSH.
#
# Two backends:
#   ollama   — what the studieplugg pipeline actually runs. Works for every model.
#   llamacpp — upstream llama.cpp, the only way to test Arc iGPU offload (-g), but it
#              cannot read Ollama's GGUF for newer architectures. qwen3.6:35b-a3b for
#              instance fails with "qwen35moe.rope.dimension_sections has wrong array
#              length", because Ollama patches architectures ahead of upstream.
#
# Usage: ./scripts/llm-bench.sh [options]
#   -b <backend>  ollama | llamacpp                           (default: ollama)
#   -m <model>    Ollama model name                           (default: llama3.3:70b)
#   -c <cpuset>   Host CPUs to pin LXC 201 to                 (default: leave as-is)
#   -t <threads>  Thread count                                (default: 6)
#   -g <ngl>      Layers to offload to the Arc iGPU (llamacpp only, 0 = CPU)
#   -n <tokens>   Tokens to generate                          (default: 128)
#   -p <words>    Prompt length in repeated sentences         (default: 120)
#   -r <reps>     Runs per measurement, first discarded       (default: 3)
#   -l <label>    Label for the results row                   (default: auto)
#
# Examples:
#   ./scripts/llm-bench.sh -m qwen3.6:35b-a3b -c 6-13 -l "MoE E-cores"
#   ./scripts/llm-bench.sh -b llamacpp -m llama3.3:70b -g 99 -l "70B iGPU"
#
# Results append to /root/llm-bench-results.tsv on pve2, one row per invocation:
# the median of the warm reps, with the spread beside it.
#
# The first rep is always discarded. It pays model load and page-faults for weights
# read off disk, which is a cold-start artifact and not a property of the model —
# mixing it in makes a fast configuration look slow. The model is therefore kept
# resident between reps (keep_alive) and unloaded again on exit.
#
# Pinning: -c changes the LXC's cpuset for the run and the ORIGINAL value is put
# back on every exit path, including Ctrl-C. Without -c the pinning is not touched
# at all. It used to restore a hardcoded 6-13, which silently moved the container
# to the E-cores once its normal home became the P-cores (0-5).
set -euo pipefail

PVE=${PVE:-192.168.10.12}
VMID=${VMID:-201}
BACKEND=ollama
MODEL=llama3.3:70b
CPUSET=""          # empty = do not touch the pinning
THREADS=6
NGL=0
NTOK=128
PWORDS=120
REPS=3
LABEL=""

while getopts "b:m:c:t:g:n:p:r:l:h" opt; do
  case $opt in
    b) BACKEND=$OPTARG ;;
    m) MODEL=$OPTARG ;;
    c) CPUSET=$OPTARG ;;
    t) THREADS=$OPTARG ;;
    g) NGL=$OPTARG ;;
    n) NTOK=$OPTARG ;;
    p) PWORDS=$OPTARG ;;
    r) REPS=$OPTARG ;;
    l) LABEL=$OPTARG ;;
    # Print the header block by where it ends, not by line number — the range went
    # stale the moment the usage text grew.
    h) sed -n '2,/^set -euo/p' "$0" | sed '$d'; exit 0 ;;
    *) exit 1 ;;
  esac
done
case "$BACKEND" in ollama|llamacpp) ;; *) echo "okänd backend: $BACKEND" >&2; exit 1 ;; esac
for pair in "REPS:$REPS" "THREADS:$THREADS" "NGL:$NGL" "NTOK:$NTOK" "PWORDS:$PWORDS"; do
  case "${pair#*:}" in ''|*[!0-9]*) echo "${pair%%:*} vill ha ett tal: ${pair#*:}" >&2; exit 1 ;; esac
done
# The cpuset is interpolated into a shell program on the far side. Digits, commas
# and dashes are the whole legal alphabet; anything else is a mistake or an attack.
case "$CPUSET" in '') ;; *[!0-9,-]*) echo "-c vill ha en cpuset som 0-5 eller 6,8: $CPUSET" >&2; exit 1 ;; esac
# One rep leaves nothing after the cold one is thrown away.
[ "$REPS" -ge 2 ] || { echo "-r måste vara minst 2 — rep 1 kastas alltid" >&2; exit 1; }
: "${LABEL:=$MODEL $BACKEND cpuset=${CPUSET:-oförändrad} t=$THREADS}"

ssh_pve() { ssh -o ConnectTimeout=10 -o BatchMode=yes "root@${PVE}" "$@"; }

blob=""
if [ "$BACKEND" = "llamacpp" ]; then
  # Ollama stores each layer as a plain file under models/blobs, and the layer with
  # mediaType application/vnd.ollama.image.model *is* the GGUF. Reusing it avoids
  # keeping a second multi-GB copy just to benchmark.
  # Library models only — a namespaced model lives under registry.ollama.ai/<ns>/...
  manifest="/opt/ai-lab/ollama/models/manifests/registry.ollama.ai/library/${MODEL/:/\/}"
  blob=$(ssh_pve "pct exec ${VMID} -- sh -c \"jq -r '.layers[] | select(.mediaType==\\\"application/vnd.ollama.image.model\\\") | .digest' ${manifest} 2>/dev/null\"" | tr ':' '-')
  if [ -z "$blob" ]; then
    echo "Hittade ingen GGUF-blob för '${MODEL}'. Är den pullad? (docker exec ollama ollama list)" >&2
    exit 1
  fi
fi

echo "==> ${LABEL}"
[ -n "$blob" ] && echo "    blob: ${blob}"

# Build the remote environment with %q rather than hand-written single quotes. -l
# takes free text, and one apostrophe in a label used to end the quoting and hand
# the rest of the label to the remote shell as code.
remote_env=$(printf 'BACKEND=%q MODEL=%q MODEL_BLOB=%q CPUSET=%q THREADS=%q NGL=%q NTOK=%q PWORDS=%q REPS=%q LABEL=%q VMID=%q' \
  "$BACKEND" "$MODEL" "$blob" "$CPUSET" "$THREADS" "$NGL" "$NTOK" "$PWORDS" "$REPS" "$LABEL" "$VMID")

# shellcheck disable=SC2029  # deliberate client-side expansion of the parameters
ssh_pve "$remote_env bash -s" <<'REMOTE'
set -euo pipefail
CPUSET_FILE=/sys/fs/cgroup/lxc/${VMID}/cpuset.cpus
OUT=/root/llm-bench-results.tsv

# Read the pinning before touching anything, so it can be put back exactly. A
# hardcoded value here moved the container to whichever cpuset was normal when the
# script was written, which stopped being true.
#
# An empty cpuset.cpus is legal under cgroup v2 — it means "inherit" — so an empty
# read is NOT the same as a failed read. Conflating them let the script pin the
# container and then decline to unpin it, which is the exact failure this rewrite
# exists to prevent. Refuse to touch the pinning we cannot restore.
if ! ORIG_CPUSET=$(cat "$CPUSET_FILE" 2>/dev/null); then
  if [ -n "$CPUSET" ]; then
    echo "kan inte läsa $CPUSET_FILE — pinnar inte om utan att kunna återställa" >&2
    exit 1
  fi
  ORIG_CPUSET=""
fi
CPUSET_CHANGED=0

cleanup() {
  # Stop the reps before undoing the conditions they run under, or the tail of the
  # series is measured on a different cpuset than the head.
  #
  # Killing the subshell is not enough: the work is three levels below it
  # (lxc-attach -> sh -> curl) and those are not in its job. Measured 2026-09-07 —
  # the shell died on TERM and five processes carried on benchmarking. The request
  # file name is unique to this script, so it is a safe thing to match on.
  if [ -n "${bench_pid:-}" ] && kill -0 "$bench_pid" 2>/dev/null; then
    kill "$bench_pid" 2>/dev/null || true
    wait "$bench_pid" 2>/dev/null || true
  fi
  pkill -f 'bench-req\.json' >/dev/null 2>&1 || true
  pct exec "${VMID}" -- pkill -f 'bench-req\.json' >/dev/null 2>&1 || true
  if [ "$CPUSET_CHANGED" = 1 ]; then
    printf '%s\n' "$ORIG_CPUSET" > "$CPUSET_FILE" 2>/dev/null || true
  fi
  # The reps need the weights resident, so keep_alive is not 0 any more. Give the
  # RAM back rather than leaving a benchmark's model loaded.
  if [ "$BACKEND" = "ollama" ]; then
    pct exec "${VMID}" -- sh -c "curl -s --max-time 30 localhost:11434/api/generate \
      -d '{\"model\":\"${MODEL}\",\"keep_alive\":0}'" >/dev/null 2>&1 || true
  fi
  pct exec "${VMID}" -- docker rm -f bench >/dev/null 2>&1 || true
}
# A handler that only runs cleanup returns to the interrupted script afterwards —
# the reps carry on against a restored cpuset and an unloaded model, and cleanup
# runs a second time at the real exit. Let the signal handlers exit and leave the
# single EXIT trap to do the work.
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Ctrl-C on the workstation does not arrive here as INT. ssh without a PTY does not
# forward the signal; it drops the connection and this shell gets SIGHUP instead.
# Untrapped, that can end the shell without the EXIT trap ever running — and the
# cpuset stays where the benchmark put it.
trap 'exit 129' HUP
# And Ctrl-C does not reliably arrive as HUP either: sshd does not always signal an
# orphaned remote command, so it runs to completion with the cpuset still changed.
# Measured 2026-09-07 — the client died, this side did not notice, four processes
# kept going. The progress dots below double as a liveness probe: once the client is
# gone the channel is closed and writing one raises SIGPIPE, which now exits through
# cleanup instead of killing the shell outright.
trap 'exit 141' PIPE

throttle() { t=0; for f in /sys/devices/system/cpu/cpu*/thermal_throttle/package_throttle_count; do [ -r "$f" ] && t=$((t + $(cat "$f"))); done; echo "$t"; }
pkgtemp()  { sensors 2>/dev/null | awk '/Package id 0/ {gsub(/[+°C]/,"",$4); print $4; exit}'; }

# Build the prompt on the target. /tmp is cleared on boot, so never assume a previous
# run left it behind. Same sentence count for every run so numbers stay comparable.
if [ "$BACKEND" = "ollama" ]; then
  pct exec "${VMID}" -- sh -c "
    P=\$(yes 'Detta ar en mening ur ett forelasningstranskript om kemiska grundamnen och periodiska systemet.' 2>/dev/null | head -${PWORDS} | tr '\n' ' ')
    jq -n --arg p \"\$P\" --arg m '${MODEL}' '{model:\$m, prompt:\$p, stream:false, keep_alive:\"10m\",
      options:{num_ctx:8192, num_predict:${NTOK}, temperature:0, num_thread:${THREADS}}}' > /tmp/bench-req.json
  "
else
  pct exec "${VMID}" -- sh -c "
    P=\$(yes 'Detta ar en mening ur ett forelasningstranskript om kemiska grundamnen och periodiska systemet.' 2>/dev/null | head -${PWORDS} | tr '\n' ' ')
    jq -n --arg p \"\$P\" '{prompt:\$p, n_predict:${NTOK}, temperature:0}' > /tmp/bench-req.json
  "
fi

if [ -n "$CPUSET" ]; then
  echo "$CPUSET" > "$CPUSET_FILE"
  CPUSET_CHANGED=1
  echo "    cpuset: $ORIG_CPUSET -> $CPUSET (återställs vid avslut)"
else
  echo "    cpuset: $ORIG_CPUSET (orörd)"
fi

if [ "$BACKEND" = "llamacpp" ]; then
  pct exec "${VMID}" -- docker rm -f bench >/dev/null 2>&1 || true
  pct exec "${VMID}" -- docker run -d --name bench \
    --device /dev/dri:/dev/dri --group-add 44 --group-add 993 \
    -v /opt/ai-lab/ollama/models/blobs:/models:ro \
    -p 127.0.0.1:8099:8080 \
    ghcr.io/ggml-org/llama.cpp:server-vulkan \
    -m "/models/${MODEL_BLOB}" --host 0.0.0.0 --port 8080 \
    -c 8192 -t "${THREADS}" -ngl "${NGL}" --parallel 1 --no-webui >/dev/null

  # Poll the health endpoint rather than tailing the log. `docker logs -f | grep -m1`
  # leaves docker blocked on a closed pipe and the pipeline hangs until its timeout.
  ready=0
  for _ in $(seq 1 180); do
    if pct exec "${VMID}" -- sh -c 'curl -sf --max-time 3 localhost:8099/health >/dev/null 2>&1'; then
      ready=1; break
    fi
    sleep 5
  done
  [ "$ready" = "1" ] || { echo "servern blev aldrig redo" >&2; exit 1; }
fi

t0=$(throttle); tmax=0

# Pipe curl straight into jq: routing the response through a shell variable lets
# dash's echo expand the \n escapes inside the JSON and corrupts the document.
#
# Ollama reports counts and nanosecond durations rather than rates, so derive the
# rates here to keep both backends in the same units.
one_rep() {
  if [ "$BACKEND" = "ollama" ]; then
    pct exec "${VMID}" -- sh -c "curl -fsS --max-time 7200 localhost:11434/api/generate -d @/tmp/bench-req.json \
      | jq -r '[.prompt_eval_count,
                (.prompt_eval_count / (.prompt_eval_duration / 1000000000)),
                (.eval_count / (.eval_duration / 1000000000))] | @tsv'"
  else
    pct exec "${VMID}" -- sh -c "curl -fsS --max-time 7200 localhost:8099/completion -d @/tmp/bench-req.json \
      | jq -r '[.timings.prompt_n, .timings.prompt_per_second, .timings.predicted_per_second] | @tsv'"
  fi
}

: > /tmp/bench-reps.tsv
(
  rep=1
  while [ "$rep" -le "$REPS" ]; do
    one_rep >> /tmp/bench-reps.tsv
    rep=$((rep + 1))
  done
) &
bench_pid=$!
# Sample the package temperature across the whole series, not one rep, so the
# thermal column still describes the load that produced the numbers.
while kill -0 $bench_pid 2>/dev/null; do
  c=$(pkgtemp); [ -n "$c" ] && [ "${c%.*}" -gt "${tmax%.*}" ] && tmax=$c
  printf '.' >&2   # progress, and the liveness probe described at the PIPE trap
  sleep 10
done
printf '\n' >&2
wait $bench_pid
t1=$(throttle)

got=$(wc -l < /tmp/bench-reps.tsv)
[ "$got" -eq "$REPS" ] || { echo "bara $got av $REPS reps gav svar — mätningen skrivs inte" >&2; exit 1; }

# Counting lines is not enough. Asking llama.cpp's /completion for .timings on an
# error object yields a row of empty fields and jq still exits 0, so every rep can
# "succeed" while measuring nothing — the ollama path fails loudly instead, because
# dividing null by a number is a jq error. Verified 2026-09-07. Require three fields
# that are actually positive numbers before anything is written down.
if ! awk -F'\t' '
  NF != 3 { exit 1 }
  $1 !~ /^[0-9]+$/ { exit 1 }
  $2 + 0 <= 0 || $3 + 0 <= 0 { exit 1 }
  $2 ~ /nan|inf/ || $3 ~ /nan|inf/ { exit 1 }
' /tmp/bench-reps.tsv; then
  echo "en rep gav inga mätvärden — svaret var troligen ett fel, inte ett resultat:" >&2
  cat /tmp/bench-reps.tsv >&2
  exit 1
fi

echo "    reps (rep 1 kastas):"
awk -F'\t' '{printf "      %d: prefill %.1f  gen %.2f%s\n", NR, $2, $3, (NR==1 ? "   <- kall" : "")}' /tmp/bench-reps.tsv

# Median over the warm reps. An even count averages the middle pair; with the
# default REPS=3 that is the mean of the two warm runs.
med() { sort -n | awk '{a[NR]=$1} END {if (NR%2) printf "%.2f\n", a[(NR+1)/2]; else printf "%.2f\n", (a[NR/2]+a[NR/2+1])/2}'; }
warm() { tail -n +2 /tmp/bench-reps.tsv | cut -f"$1"; }

prompt_n=$(tail -n 1 /tmp/bench-reps.tsv | cut -f1)
prefill_med=$(warm 2 | med)
gen_med=$(warm 3 | med)
gen_min=$(warm 3 | sort -n | head -1 | awk '{printf "%.2f\n", $1}')
gen_max=$(warm 3 | sort -n | tail -1 | awk '{printf "%.2f\n", $1}')

HEADER='label\treps\tprompt_n\tprefill_med\tgen_med\tgen_min\tgen_max\tmax_temp_C\tthrottle_events'
# The row grew columns when reps arrived. Rather than append rows that do not line
# up with the old header, retire the old file once and start a clean one.
if [ -s "$OUT" ] && [ "$(head -1 "$OUT")" != "$(printf "$HEADER")" ]; then
  mv "$OUT" "${OUT%.tsv}-pre-reps.tsv"
  echo "    tidigare resultat (utan reps) flyttade till ${OUT%.tsv}-pre-reps.tsv"
fi
[ -s "$OUT" ] || printf "$HEADER\n" > "$OUT"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$LABEL" "$REPS" "$prompt_n" "$prefill_med" "$gen_med" "$gen_min" "$gen_max" "$tmax" "$((t1 - t0))" >> "$OUT"
column -t -s "$(printf '\t')" "$OUT"
REMOTE
