# ADR-003: LLM Inference Tuning on ai-lab — Threads, Speculative Decoding, and the Bandwidth Wall

## Status

**Accepted** (2026-09-03)

## Context

Three questions arrived together and turned out to share one answer.

1. A YouTube video ("THREE FREE SPEED TRICKS") recommended **speculative decoding /
   MTP** as the top way to speed up a local LLM. Was it worth adopting on ai-lab?
2. A block of third-party optimisation advice suggested `--mlock`, `--no-mmap`,
   quantised KV cache, flash attention, core pinning to the P-cores, OpenVINO/SYCL
   backends, XMP memory profiles, and a Windows power plan.
3. Was pinning LXC 201 to the six P-cores actually a good idea?

ai-lab is LXC 201 on pve2: Intel Arrow Lake, **6 P-cores (0-5) + 8 E-cores (6-13)**,
no SMT, **DDR5-4800 dual channel (~77 GB/s)**, 52 GB RAM, no discrete GPU. The LXC's
cgroup cpuset is host CPUs 0-5.

The governing physical fact: **token generation is bandwidth-bound**. Decode speed is
essentially *bytes read per token ÷ memory bandwidth*. Almost every tuning question
below reduces to that.

## Decision

1. **Do not adopt speculative decoding in any form.** Not a draft model, not the
   checkpoint's MTP head, not n-gram speculation. Measured slower or neutral on the
   model actually in production.
2. **Cap the Ollama runner's thread count globally** via `LLAMA_ARG_THREADS`, set to
   `ai_lab_num_thread` in the compose template.
3. **Keep the MoE** (`qwen3.6:35b-a3b`) as the pipeline model. Confirmed, not revisited.
4. **Keep the P-core pinning**, but stop treating it as a large win — it is worth
   16-29%, not an order of magnitude.

### 1. The thread bug — the only significant win found

Ollama passes `-t` to its embedded `llama-server` **only** when a request supplies
`num_thread`. Otherwise it leaves auto-detection to llama-server, which reads
`/proc/cpuinfo`. lxcfs masks `nproc` (reports 6) but **not** `/proc/cpuinfo` (still
shows the host's 14). So the runner starts 14 threads inside a 6-CPU cgroup.

ggml's thread barrier busy-polls rather than sleeping, so threads that cannot be
scheduled burn the very cores the working threads need. The result is not a gentle
degradation:

| model | 6 threads | auto-detected (14) | factor |
|---|---|---|---|
| `qwen3.6:35b-a3b` | 15.44 tok/s | 0.06 tok/s | ~257x |
| `qwen3:8b` | 6.8 tok/s | 0.15 tok/s | ~45x |

Verified control vs treatment on a throwaway container, production untouched:

```
without LLAMA_ARG_THREADS:  n_threads = 14 (n_threads_batch = 14) / 14
with    LLAMA_ARG_THREADS=6: n_threads = 6  (n_threads_batch = 6)  / 14
```

**Who was affected.** `studieplugg` and `lecture.sh` send `num_thread` themselves and
were always fine — which is exactly why this went unnoticed. **Karakeep** and
**Open WebUI** reach Ollama through the OpenAI-compatible API, which has no such
field. They could not opt in and were silently getting the collapsed path.

Ollama has no `OLLAMA_NUM_THREAD` env var. `LLAMA_ARG_THREADS` works because Ollama
hands its own environment to the `llama-server` subprocess, which reads that variable
natively. An explicit per-request `num_thread` still overrides it.

### 2. Speculative decoding — measured, rejected

Measured on `qwen3.6:35b-a3b`, 6 threads, `think:false`, 3 prompts × 4 reps, first
rep discarded as cold:

| config | sammanfatta | extrahera | prosa | **overall** | vs baseline |
|---|---|---|---|---|---|
| no speculation | 14.62 | 14.73 | 15.41 | **14.73** | — |
| `ngram-simple` | 14.39 | 13.72 | 15.33 | **14.39** | 0.98x |
| `draft-mtp` | 10.86 | 13.79 | 7.67 | **10.86** | **0.74x** |

Prefill essentially unaffected (84.3 → 81.7 tok/s).

Draft acceptance is strongly task-dependent, and the worst case is the common one:

| config | sammanfatta | extrahera | prosa |
|---|---|---|---|
| `ngram-simple` | never engaged | 6.2% | never engaged |
| `draft-mtp` | 29.3% | 47.0% | **8.6%** |

On free prose, MTP halves throughput (7.67 vs 15.41) because it drafts three tokens,
gets one, and pays for the rest.

**Why this is structural, not bad luck.** Speculative decoding pays off when the
target model is so bandwidth-bound that verifying N tokens costs nearly the same as
generating 1. That describes large *dense* models. An A3B MoE activates only ~3B
parameters per token, so per-token cost is already small and the draft's extra
forward pass becomes pure overhead. **Choosing a MoE solves the same problem
speculative decoding solves — you do not get both.**

The dense comparison run alongside it: `DeepSeek-R1-Distill-Qwen-32B-Q4_K_M` measured
**1.08 tok/s**, 14x slower than the MoE, because it reads all ~20 GB of weights per
token. 192 tokens takes three minutes. Even an optimistic 2x from speculation lands
at ~2 tok/s — still unusable interactively.

**Losslessness did not hold in practice.** At temperature 0, `draft-mtp` produced
*different text* from the baseline on 2 of 3 prompts (the extraction prompt matched
exactly). Likely mechanism: batched verification changes floating-point accumulation
order, flipping near-tied token choices and diverging from there. **This was not
isolated** — it could equally be a bug in Ollama's fork. That is the thread to pull
if anyone revisits this.

### 3. The pasted optimisation advice, item by item

| advice | verdict |
|---|---|
| Flash attention, quantised KV cache | **Keep.** Already on. |
| Core pinning to P-cores | **Real but modest.** See below. |
| `--mlock` / `--no-mmap` | **Marginal.** 19-30 GB free; nothing is being evicted. Also `--mlock` is deprecated in favour of `--load-mode`. |
| Enable XMP/EXPO in BIOS | **Nothing to gain.** The modules are `CT32G48C40S5` — JEDEC DDR5-4800, already at rated speed. There is no profile to switch on. |
| Windows power plan | **N/A.** This is Linux. |
| OpenVINO / SYCL backends | **Already settled for Whisper** (OpenVINO CPU won, see the ai_lab role). For the LLM the bandwidth wall applies regardless of backend. |
| iGPU offload (Vulkan) | **Dead end.** The Arc iGPU shares the same DDR5 controller, so it has no bandwidth advantage to trade for weaker compute. Independently confirmed 2026-08-28. |

### 4. P-core pinning, and a correction to earlier notes

Measured with the LXC given exclusive use of each set, `-t 6`:

| cpuset | decode tok/s | prefill tok/s |
|---|---|---|
| P-cores `0-5` | 15.44 | 314.8 |
| E-cores `6-13` | 13.01 | 223.0 |

So the hybrid-topology penalty is **16% decode / 29% prefill** — worth having, not
transformative.

This **corrects** a note previously in `ai_lab/defaults/main.yaml` that recorded
0.22-0.25 tok/s on the E-cores as "reproducible, and unexplained". Two separate
effects were being read as one:

1. **Oversubscription** — the thread bug above. Not an E-core property; the same
   collapse happens on the P-cores.
2. **Contention** — the arr-stack LXC (200) is also pinned to `6-13`, so an E-core
   run was never alone on those cores.

The rule is therefore not "avoid E-cores", it is **never let the thread count exceed
the cpuset**.

Note also that the P-core lock is **not exclusive**: k3s VMs 100/101 and VM 105 have
no CPU affinity at all and can be scheduled onto 0-5. And the current layout
(ai-lab on P-cores, arr-stack on E-cores) is the reverse of the documented 2026-07-01
design intent, which reserved the P-cores for k3s.

## Alternatives Considered

**A draft model in the Qwen3.6 family.** Impossible — the smallest Qwen3.6 is 27b.
And pointless for an A3B MoE for the reasons above.

**`PARAMETER num_thread 6` baked into models via `ollama create`.** Works, and it
would cover the OpenAI-compatible callers. Rejected: `PullModel()` fetches the
registry manifest for the same name, so the next `ollama pull` of that tag silently
reverts the fix. A time bomb. A separate derived tag (`qwen3:8b-t6`) would survive
but forces every consumer to change its model name.

**Docker `--cpuset-cpus` on the Ollama container.** Does not help. The runner already
has affinity `0-5` and still picks 14 — the detection reads `/proc/cpuinfo`, not the
cgroup or `sched_getaffinity`.

**Running speculation through upstream llama.cpp instead of Ollama.** Not possible for
this model: the MoE GGUF fails to load upstream with `qwen35moe.rope.dimension_sections
has wrong array length; expected 4, got 3`. Only Ollama's fork can read it. And
Ollama's HTTP API does not expose `--spec-type` anyway, so speculation is unreachable
from the production path regardless of whether it helped.

## Consequences

- Every Ollama caller now gets a sane thread count, including the ones that cannot
  ask for one. This is the single largest available win and it costs nothing.
- Speculative decoding is closed as a question. Do not re-test it without new
  hardware or a dense model, and re-read the "why this is structural" paragraph first.
- **The only remaining lever that matters is memory bandwidth** — not more threads,
  not draft models, not the iGPU. That points at the mini-ITX 9950X build already in
  the hardware backlog (DDR5-6000, ~96 GB/s vs the current ~77).
- Open question left behind: whether MTP's output divergence at temperature 0 is
  floating-point tie-breaking or a fork bug.

## Method Notes

Worth recording, because two of these invalidated whole runs before being caught.

- **`--spec-type` defaults to `none`** in llama.cpp before b10223. Passing `-md
  draft.gguf` loads the draft model and logs `loading draft model` while never using
  it. An entire three-hour A/B measured nothing before this surfaced. Fixed upstream
  in PR #26814. **Always check `draft_n` in `.timings`** — absent or zero means
  speculation never ran.
- **Reasoning models put their text in `reasoning_content`, not `content`.** Hashing
  `content` alone yields the sha256 of a single newline for every run, which looks
  like a perfect losslessness result and is not.
- `/completion` does not apply the chat template; `/v1/chat/completions` does. Raw
  completions against a chat-tuned model produce 3-token stubs.
- Discard the first rep of every arm — always, per standing preference.
- Verify nothing else is running first. An orphaned `llama-server` at 600% CPU
  survived `ollama stop` and quietly poisoned one round of measurements.

Raw data: `/opt/ai-lab/bench/spec/` on ai-lab (`moe-spec.tsv` is the one that counts).
