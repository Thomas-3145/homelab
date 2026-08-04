# Runbook — Study pipeline (Whisper + local LLM)

Turns recorded lectures into study material: transcript, summary, key points and
exam questions. Whisper runs on pve3, the LLM on pve2, and both are driven from the
workstation by helpers in `~/dev/dotfiles/zsh/.zshrc`.

Every number below was measured on 2026-08-03/04. Where a setting looks wrong, it is
almost certainly deliberate — the "obvious" faster choice was tried and reverted.

## Layout

| Where | What |
|---|---|
| **whisper** — LXC 202, pve3, `192.168.10.42:9000` | Whisper large-v3, CPU. Tailscale `100.99.245.13` |
| **ai-lab** — LXC 201, pve2, `192.168.10.41` | Ollama `:11434`, Open WebUI `:3000`. Tailscale `100.70.167.71` |
| `ansible/roles/whisper/`, `ansible/roles/ai_lab/` | Both are Ansible-managed; never edit the scripts on the box |
| `/opt/ai-lab/{inbox,out,work}` | Input per lecture, results, scratch |

Transcription is on pve3 on purpose: it is CPU-bound and pve2 is the only DDR5 host,
so pve2's cores and RAM belong to the model. One lecture can transcribe on pve3 while
the previous one is summarised on pve2.

## Daily use

```bash
# whole lecture (video parts + slide PDF), start → wait → fetch → file away
studieplugg-lecture-allt F6 ~/studier/sommarkurser/grundämnen/föreläsningar

# same but detached — you can close the laptop; ntfy pings when done
studieplugg-lecture F6 ~/studier/sommarkurser/grundämnen/föreläsningar
studieplugg-get
```

Files must match `<name>*` for the helper's glob to pick them up. A lecture video
called `Föreläsning 7.mp4` will **not** be copied for `F7` — rename it `F7_del_1.mp4`.
The slide PDF is optional but worth having: it grounds terminology and fixes what
Whisper mishears.

The helpers pin LXC 201 to the P-cores (host CPUs `0-5`) for the duration of a run and
release it back to the E-cores afterwards.

## Settings that are load-bearing

In `ansible/roles/ai_lab/defaults/main.yaml`. Do not change these on speed grounds
alone — each was measured on output quality.

| Setting | Value | Why |
|---|---|---|
| `ai_lab_llm_model` | `qwen3.6:35b-a3b` | MoE: 36B parameters, ~3B active per token. 21x faster prefill and 17.6x faster generation than `llama3.3:70b`, **and** better output. One lecture: ~149 min → ~17 min |
| `ai_lab_num_ctx` | `32768` | 8192 truncated the summary mid-heading (`truncated = 1`) |
| `ai_lab_num_thread` | `6` | Generation is a per-token barrier and does not parallelise. 14 threads measured 6.3 tok/s against 6 threads at 14.2. Ollama autodetects too many if this is unset |
| `think:false` (in the templates) | on | qwen3.6 reasons into a separate `thinking` field and only writes `response` when finished. Without this a reduce step spent all 8192 context tokens deliberating and returned an **empty file** |
| `ai_lab_chunk_words` | `3000` | See below |
| `ai_lab_vision_slides` | `0` | See below |

### Why chunking stays on

A whole lecture (longest is 13,169 words ≈ 18k tokens) now fits in 32768, so
single-pass is possible. It was tried and reverted: the F1 summary lost the course
code, the excursion details and the Oddo-Harkins rule.

Map-reduce has a property that looks like pure loss but is not — it **guarantees
coverage**. Every chunk is summarised on its own, so nothing can be skipped. Handed
the whole transcript at once the model compresses harder and drops things itself.

### Why vision is off

The model can read images, and the code to send figure-heavy slides is still in
`studieplugg-lecture.j2` (`ollama_gen_vision`, pages ranked by `pdfimages -list`).
It is disabled because it measured *worse*: eight images cost ~6000 context tokens,
cut generation from 14.2 to 5.0 tok/s, and crowded out the slide text — every course
detail vanished (Athena, Ytterby, KZ1001, Oddo-Harkins: 2 hits each → 0).

**Caveat: the mechanism was never isolated.** That same run also switched to
single-pass, so the regression may belong to either change. Re-testing means running
single-pass with `VISION_SLIDES=0` as the control first — one variable at a time.

## Live lectures

Two scripts in `~/studier/sommarkurser/grundämnen/inspelning/`, run in separate
terminals: `zoom-live-transcribe.sh` captures Zoom audio to a growing transcript, and
`question-watch.sh` follows it, spots questions the lecturer asks and answers them
from the course material. See the README there.

## Traps

- **`${#arr[@]}` in a `.j2`** kills the template with "Missing end of comment tag" —
  Jinja reads the brace-hash as a comment opener. Test with `[[ -n "${arr[*]:-}" ]]`.
- **`echo "$json"` under dash** expands the `\n` escapes and corrupts the document.
  Pipe `curl` straight into `jq`.
- **Ansible can report `failed=1` and still look applied.** Always verify the
  deployed script on the box afterwards.
- **`pct exec` gives no login shell** — use the full path, `/usr/local/bin/...`.
- **Never run 8 threads against the E-core cpuset (`6-13`)**: reproducibly 0.22 tok/s
  generation, ~50x worse than 6 threads on the same cores, with normal prefill.
  Unexplained.
- `/tmp` is cleared on boot; scripts must not assume a previous run left files there.

## Related

- pve2's CPU power limit — `docs/`, memory `todo-pve2-thermal`. It is capped at 45 W
  and costs under 1% throughput; do not raise it without re-measuring.
- `scripts/llm-bench.sh` — benchmark harness. Records tok/s alongside peak temperature
  and throttle delta, so a fast number bought with throttling is visible.
