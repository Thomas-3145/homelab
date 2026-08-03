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
#   -c <cpuset>   Host CPUs to pin LXC 201 to                 (default: 6-13, E-cores)
#   -t <threads>  Thread count                                (default: 6)
#   -g <ngl>      Layers to offload to the Arc iGPU (llamacpp only, 0 = CPU)
#   -n <tokens>   Tokens to generate                          (default: 128)
#   -p <words>    Prompt length in repeated sentences         (default: 120)
#   -l <label>    Label for the results row                   (default: auto)
#
# Examples:
#   ./scripts/llm-bench.sh -m qwen3.6:35b-a3b -c 6-13 -l "MoE E-cores"
#   ./scripts/llm-bench.sh -b llamacpp -m llama3.3:70b -g 99 -l "70B iGPU"
#
# Results append to /root/llm-bench-results.tsv on pve2. Restores the normal E-core
# pinning on every exit path, including Ctrl-C.
set -euo pipefail

PVE=${PVE:-192.168.10.12}
VMID=${VMID:-201}
BACKEND=ollama
MODEL=llama3.3:70b
CPUSET=6-13
THREADS=6
NGL=0
NTOK=128
PWORDS=120
LABEL=""

while getopts "b:m:c:t:g:n:p:l:h" opt; do
  case $opt in
    b) BACKEND=$OPTARG ;;
    m) MODEL=$OPTARG ;;
    c) CPUSET=$OPTARG ;;
    t) THREADS=$OPTARG ;;
    g) NGL=$OPTARG ;;
    n) NTOK=$OPTARG ;;
    p) PWORDS=$OPTARG ;;
    l) LABEL=$OPTARG ;;
    h) sed -n '2,30p' "$0"; exit 0 ;;
    *) exit 1 ;;
  esac
done
case "$BACKEND" in ollama|llamacpp) ;; *) echo "okänd backend: $BACKEND" >&2; exit 1 ;; esac
: "${LABEL:=$MODEL $BACKEND cpuset=$CPUSET t=$THREADS}"

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

# shellcheck disable=SC2029  # deliberate client-side expansion of the parameters
ssh_pve "BACKEND='${BACKEND}' MODEL='${MODEL}' MODEL_BLOB='${blob}' CPUSET='${CPUSET}' THREADS='${THREADS}' NGL='${NGL}' NTOK='${NTOK}' PWORDS='${PWORDS}' LABEL='${LABEL}' VMID='${VMID}' bash -s" <<'REMOTE'
set -euo pipefail
CPUSET_FILE=/sys/fs/cgroup/lxc/${VMID}/cpuset.cpus
OUT=/root/llm-bench-results.tsv

cleanup() {
  echo "6-13" > "$CPUSET_FILE" 2>/dev/null || true
  pct exec "${VMID}" -- docker rm -f bench >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

throttle() { t=0; for f in /sys/devices/system/cpu/cpu*/thermal_throttle/package_throttle_count; do [ -r "$f" ] && t=$((t + $(cat "$f"))); done; echo "$t"; }
pkgtemp()  { sensors 2>/dev/null | awk '/Package id 0/ {gsub(/[+°C]/,"",$4); print $4; exit}'; }

# Build the prompt on the target. /tmp is cleared on boot, so never assume a previous
# run left it behind. Same sentence count for every run so numbers stay comparable.
if [ "$BACKEND" = "ollama" ]; then
  pct exec "${VMID}" -- sh -c "
    P=\$(yes 'Detta ar en mening ur ett forelasningstranskript om kemiska grundamnen och periodiska systemet.' 2>/dev/null | head -${PWORDS} | tr '\n' ' ')
    jq -n --arg p \"\$P\" --arg m '${MODEL}' '{model:\$m, prompt:\$p, stream:false, keep_alive:\"0\",
      options:{num_ctx:8192, num_predict:${NTOK}, temperature:0, num_thread:${THREADS}}}' > /tmp/bench-req.json
  "
else
  pct exec "${VMID}" -- sh -c "
    P=\$(yes 'Detta ar en mening ur ett forelasningstranskript om kemiska grundamnen och periodiska systemet.' 2>/dev/null | head -${PWORDS} | tr '\n' ' ')
    jq -n --arg p \"\$P\" '{prompt:\$p, n_predict:${NTOK}, temperature:0}' > /tmp/bench-req.json
  "
fi

echo "$CPUSET" > "$CPUSET_FILE"

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
if [ "$BACKEND" = "ollama" ]; then
  pct exec "${VMID}" -- sh -c "curl -s --max-time 7200 localhost:11434/api/generate -d @/tmp/bench-req.json \
    | jq -r '[.prompt_eval_count,
              (.prompt_eval_count / (.prompt_eval_duration / 1000000000)),
              (.eval_count / (.eval_duration / 1000000000))] | @tsv'" > /tmp/bench-out.txt &
else
  pct exec "${VMID}" -- sh -c "curl -s --max-time 7200 localhost:8099/completion -d @/tmp/bench-req.json \
    | jq -r '[.timings.prompt_n, .timings.prompt_per_second, .timings.predicted_per_second] | @tsv'" > /tmp/bench-out.txt &
fi
bench_pid=$!
while kill -0 $bench_pid 2>/dev/null; do
  c=$(pkgtemp); [ -n "$c" ] && [ "${c%.*}" -gt "${tmax%.*}" ] && tmax=$c
  sleep 10
done
wait $bench_pid
t1=$(throttle)

[ -s "$OUT" ] || printf 'label\tprompt_n\tprefill_tps\tgen_tps\tmax_temp_C\tthrottle_events\n' > "$OUT"
printf '%s\t%s\t%s\t%s\n' "$LABEL" "$(cat /tmp/bench-out.txt)" "$tmax" "$((t1 - t0))" >> "$OUT"
column -t -s "$(printf '\t')" "$OUT"
REMOTE
