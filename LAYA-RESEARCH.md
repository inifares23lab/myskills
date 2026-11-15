# Laya Research Report

Companion to `LAYA.md` (the question sheet). Researched 2026-09-22 against primary
sources: the [Laya model card](https://huggingface.co/convaiinnovations/laya),
[BENCHMARKS.md](https://github.com/NandhaKishorM/laya/blob/main/BENCHMARKS.md), the
official fine-tuning notebook, llama.cpp supported-models docs, TypeSafe Jev
primitives docs, and this repo's `Integrating Jev into OpenCode.txt`.

---

## 0. TL;DR — the reframe that changes everything

**Laya is not a language model you chat with.** It is a non-autoregressive
**System 1 decision model**: give it a *state* (text, email, ticket, JSON) and
*typed questions*; it returns typed answers with calibrated probabilities in a
**single forward pass** (~33 ms on a T4). It never generates text — nothing to
parse, nothing to hallucinate.

Consequences for every question in `LAYA.md`:

| Your question | Reality |
| --- | --- |
| Use Laya for code AI workflows? | Yes — as **router, guardrail, verifier, extractor**. Not as a code generator. The generative models already in OpenCode (big-pickle, muse, nemotron, jev-1.13-free) stay. |
| Deploy with llama.cpp? | **Wrong tool.** The decision head is not portable to GGUF. Use `pip install laya`. |
| Fine-tune with LoRA on 4 GB? | Yes for the head / LoRA-on-encoder. Full RLCD: run the official notebook on Kaggle 2×T4 — it takes **4–6 minutes** and is free. |
| Train toward 800M? | 800M is not a Laya size. The checkpoints are **322M and 421M**. Cap at 421M. |
| Replace Jev? | Drop-in swap for Jev's role (same `choice`/`score`/`noul` primitives), open weights, $0, 6–8× faster — except above ~20 options, where Jev wins. |

Recommended immediate path (matches your *prototype now, learn the stack* goal):

1. `pip install laya` and run the Router quickstart locally (~15 min).
2. Run the official fine-tuning notebook on Kaggle 2×T4 as-is (~1 h including setup).
3. Build the intent-gate plugin for OpenCode (§3.1) pointing at a local Laya sidecar.

---

## 1. Model Capabilities & Configurations

### 1.1 Architecture in one paragraph

Backbone encoder (ModernBERT-large, 395M, bidirectional, fully fine-tuned) plus a
decision head trained from scratch: 2 transformer layers, an option-marker scorer,
and an act/escalate head — 421M total. Every answer option is scored at its own
`[MASK]` token, then softmaxed over that question's options. **The answer space is
defined at request time**, so new schemas need no retraining. Training is RLCD
(Reinforcement Learning for Calibrated Decisions): the policy reports a
distribution, Gaussian noise is added for exploration, and the reward is a
strictly proper scoring rule (log + spherical, plus ranked probability score for
ordinal questions) — so the only way to maximise reward is to report honest
probabilities.

### 1.2 The three checkpoints

This repo holds all three; only the subfolder you request is downloaded.

| Checkpoint | Backbone | Params | Context | Best at | Download |
| --- | --- | --- | --- | --- | --- |
| `convaiinnovations/laya` (root) | ModernBERT-large | 421M | 512 | English text, guardrails, email triage | ~808 MB |
| `laya-multilingual` (subfolder) | mmBERT-base | 322M | 1024 (encoder up to 8k) | 100+ languages, ~2.2× faster | ~647 MB |
| `laya-typed-decisions` (subfolder) | ModernBERT-large | 421M | 1024 | the 4 typed-decisions workflows (0.766 acc) | ~800 MB |

Weights ship ≈ fp16 (808 MB / 421M ≈ 2 bytes per param).

### 1.3 Configuration options

**Question level** (same shape as TypeSafe Jev — this is the compatible part):

| Type | Answers | Returns |
| --- | --- | --- |
| `choice` | Which of these options? | `choice`, `probabilities`, `confidence` |
| `score` | Which level on an ordered spectrum? | `score`, `legend`, `probabilities`, `confidence` |
| `noul` | Is this true? | `noul` (0–1 probability) |

Each question: an ID you choose, `type`, `instructions` (the judgment to make),
`criteria` (options / levels / yes-no clarification). Multiple questions are
answered in **one forward pass**.

**Runtime level:**

```python
router = Router(preload=True)            # all checkpoints resident; language flips cost <1 ms
router = Router(preload=True, device="cuda")
router = Router(max_loaded=2)            # LRU: keep two hot (default 1)
router.preload(["english", "multilingual"])
router.attach("english", existing_agent) # share VRAM with an already-built agent
router.unload()                          # free memory

agent = laya.load("convaiinnovations/laya")                    # single-checkpoint mode
agent = laya.load("convaiinnovations/laya", subfolder="typed-decisions")
agent.cfg["head_max_len"] = 512          # runtime knob — see §2.4 context limits
```

**Model config knobs** (`rl_agent_config.json`): `max_len` (total context),
`head_max_len` (per-question option-prompt budget), `gradient_checkpointing`,
`max_tokens_per_batch`, `temperature` (per-question-type calibration).

### 1.4 Trade-offs & which configuration for which use case

| Configuration | Use when | Avoid when |
| --- | --- | --- |
| `Router(preload=True)` | Mixed-language traffic; production serving; you don't want to think about it | You know the language and want minimum RAM — load one checkpoint directly |
| `laya` (English root) | English-only pipelines, guardrails, email triage | Any non-English input — it collapses while staying confident (Khmer: 0.000 accuracy at 0.952 confidence) |
| `laya-multilingual` | 100+ languages; CPU serving (193–464 ms vs English CPU numbers); 1024-token states | English-heavy work — it's weaker in English (MASSIVE en 0.657 vs 0.783) |
| `laya-typed-decisions` | Agent-trace, customer-service, invoice, security-incident judgments | Generic use — it's specialised; base checkpoints beat it on broad tasks |
| Single-checkpoint mode (`laya.load`) | One dedicated pipeline, minimal RAM | Mixed traffic — use the Router |

### 1.5 Accuracy benchmarks (official, measured on a Tesla T4)

Shared benchmark, 17,416 questions, identical questions per model:

| Benchmark / Task | `laya` | `laya-multilingual` | Router |
| --- | --- | --- | --- |
| MASSIVE intent, English | **0.783** | 0.657 | 0.783 |
| MASSIVE intent, 13 other languages | 0.306 | **0.451** | 0.451 |
| XNLI, English | **0.860** | 0.843 | 0.860 |
| XNLI, 14 other languages | 0.521 | **0.731** | 0.731 |
| Languages usable (>3× random) | 23 / 51 | **45 / 51** | 45 / 51 |

Application themes (400 cases each, all three checkpoints):

| Theme | laya | laya-multi | typed-decisions | Notes |
| --- | --- | --- | --- | --- |
| Email spam | **0.993** | 0.993 | 0.958 | in training mix — production-grade |
| Phishing | 0.980 | **0.993** | 0.940 | in training mix |
| Guardrails (jailbreak) | 0.708 | 0.755 | **0.762** | **held out** — honest number |
| Moderation (toxicity) | **0.530** | 0.525 | 0.530 | **held out — barely above chance** |
| RAG passage relevance | 0.625 | **0.657** | 0.625 | |
| Support triage (10-way) | 0.502 | **0.522** | 0.505 | |
| Model routing (domain) | 0.639 | 0.123 | **0.659** | held out |

### 1.6 Performance benchmarks (latency / throughput)

Tesla T4, byte-identical questions per run:

| Questions per call | `laya` | `laya-multilingual` |
| --- | --- | --- |
| 1 | 39.5 ms | **32.8 ms** |
| 5 | 84.5 ms | **40.1 ms** |
| 10 | 158.6 ms | **72.3 ms** |
| 50 | 771 ms | **337 ms** |

103–332 questions/sec batched on one T4. CPU (Router preloaded): **193–464 ms**
per request — fine for a prototype, too slow for a per-tool-call gate at high
volume. Your RTX 3050 Ti should land near T4 numbers (±30%).

Reference: TypeSafe Jev independently measured at **236–276 ms p50** ([AbdelStark](https://github.com/AbdelStark/jev-benchmarks), [nibzard](https://github.com/nibzard/decision-model-benchmark)) → Laya answers a single question **6–8× faster**.

### 1.7 Memory footprint

| Mode | RAM/VRAM |
| --- | --- |
| `laya` (English) loaded | ~0.8 GB weights + activations ≈ **1.2–1.5 GB** |
| `laya-multilingual` loaded | ~0.65 GB weights ≈ **1.0–1.3 GB** |
| `Router(preload=True)` all checkpoints | ~1.5–2 GB |
| `Router()` lazy, `max_loaded=1` | ~1 GB — but a **7.4 s (CPU) / 10.3 s (T4) reload on every language switch** |
| Fine-tuning (full RLCD, fp16 + AdamW + activations) | ~6–7 GB → not on 4 GB VRAM (§5) |

### 1.8 Edge cases: where Laya struggles vs TypeSafe Jev

| Dimension | Winner | Detail |
| --- | --- | --- |
| >20 options in one question | **Jev** | Banking77: Jev 0.870 (72 labels) vs Laya 0.425 (77 labels). Options share a fixed `head_max_len` budget — 77 options get ~3–4 tokens each and stop being distinguishable. Jev supports 255 options out of the box. Mitigation: raise `head_max_len` to 512 / `max_len` up to 8192 (multilingual), or split into two-step coarse-to-fine choice. |
| Soft distribution matching | **Jev** | typed-decisions soft acc: Jev 0.580 vs Laya 0.471 (Laya wins argmax 0.766 vs 0.727) |
| Out-of-box calibration | **Jev** | raw ECE 0.144 vs Laya 0.213. Laya's 0.081 comes *after* a temperature refit you must do yourself |
| Option-order robustness | **Jev** | Laya changes answers more under option permutation (0.15 vs 0.13 on massive_intent.en; worse elsewhere) |
| Argmax accuracy | **Laya** | typed-decisions 0.766 vs 0.727; AG News 0.950 vs 0.910; DAIR Emotion 0.595 vs 0.480 |
| Speed | **Laya** | 6–8× faster |
| Calibration after refit | **Laya** | ECE 0.081 vs 0.246 |
| Languages | **Laya** | 45/51 usable; Jev has no published multilingual benchmark |
| Weights / cost | **Laya** | Apache 2.0, self-hosted, $0 vs closed API at $0.042/1M tokens |

### 1.9 Where the benchmarks live

- **Official:** [BENCHMARKS.md](https://github.com/NandhaKishorM/laya/blob/main/BENCHMARKS.md) + raw JSON runs in `research/results/` (T4 Colab, CPU 51-language sweep, applications) + model-card tables. All Laya-vs-Jev Jev figures are third-party *published* numbers, never re-measured by the Laya authors.
- **Community:** AbdelStark/jev-benchmarks and nibzard/decision-model-benchmark (Jev side); Hugging Face Spaces: `mayafree/typed-decision-leaderboard`, `BunsDev/laya-calibration-lab`, `multimodalart/jev-decision-index`; write-up on [Dev.to](https://dev.to/nandakishor_m_6cc0adfde9f/i-built-non-autoregressive-decision-models-a-year-ago-then-a-frontier-lab-called-it-a-18me).
- **Known failure modes (stated plainly by the authors):** base checkpoints near chance on typed-decisions zero-shot (0.362 vs 0.461 majority baseline — the 0.766 belongs to the fine-tuned checkpoint); moderation collapses on held-out data (0.530, macro-F1 0.400); keep `choice` under ~20 options; ships over-confident; ordinal `score` weakest (SST-5 0.372); English checkpoint collapses outside English while staying confident.

---

## 2. Local Deployment

### 2.1 Reality check: llama.cpp is the wrong tool for Laya

llama.cpp supports BERT-family encoders for embeddings (PR #5423) and its
ModernBERT/mmBERT support is actively evolving. But even a perfect GGUF of the
encoder gives you **nothing usable**: Laya's actual product is the decision head —
option-marker positions scored at `[MASK]` tokens, per-question softmax over the
options you sent, plus the act/escalate head. None of that exists in llama.cpp's
graph. You would have to reimplement the scoring pipeline in C++ or externally —
a research project, not a deployment.

**Verdict: skip llama.cpp.** The `laya` pip package *is* the runtime. It is
already small (421M, single forward pass, no autoregressive loop) — llama.cpp's
usual advantages (KV-cache reuse, quantized decoding) don't apply to a model with
no decoding loop.

If you insist on GGUF for the encoder alone (embeddings/similarity use, not
decisions): `python convert_hf_to_gguf.py <local-dir> --outtype f16` against a
snapshot of the `encoder/` subfolder, run via `llama-embedding`. Expect friction;
ModernBERT conversion is not in the documented supported list. ~30 min to try,
not guaranteed to land.

### 2.2 Recommended path: `pip install laya` (step by step)

Requirements (per the repo README): **Python ≥ 3.10**, `torch` 2.14,
`transformers` 5.x, `huggingface_hub` 1.x — the interpreter floor comes from those.

```bash
# 1. Environment
python3 -m venv ~/.venvs/laya && source ~/.venvs/laya/bin/activate
pip install -U "laya>=0.1.6" "transformers>=4.48.0" "datasets>=3.0.0" \
    safetensors huggingface_hub accelerate scipy pandas
# (the official notebook pins exactly these; repo README targets torch 2.14 / transformers 5.x)

# 2. First run — downloads the checkpoint (~808 MB for English)
export USE_TF=0        # see troubleshooting: TF deadlock
python - <<'EOF'
import laya
agent = laya.load("convaiinnovations/laya")   # add device="cuda" for GPU
state = {"body": "Refactor src/auth.ts to use HMAC sessions, do not touch the DB schema."}
questions = {
    "change_type": {"type": "choice", "instructions": "What kind of change?",
        "criteria": {"refactor": "restructure without behaviour change",
                     "feature": "new behaviour", "bugfix": "fix broken behaviour",
                     "out_of_scope": "none of these"}},
    "db_touched": {"type": "noul", "instructions": "Does the request require DB schema changes?"},
    "risk": {"type": "score", "instructions": "Blast radius of this change?",
        "criteria": ["single file", "one module", "cross-module", "system-wide"]},
}
print(agent.predict(state, questions)["answers"])
EOF
```

For a persistent service (what the OpenCode integration in §3 calls):

```python
# laya_server.py — FastAPI sidecar
from fastapi import FastAPI
from pydantic import BaseModel
import laya

agent = laya.load("convaiinnovations/laya", device="cuda")  # or "cpu"
app = FastAPI()

class Req(BaseModel):
    state: dict | str
    questions: dict
    model: str | None = None      # "english" | "multilingual" | "typed-decisions"

@app.post("/predict")
def predict(req: Req):
    return agent.predict(req.state, req.questions)
# uvicorn laya_server:app --port 8321
```

### 2.3 System requirements per method

| Method | CPU | RAM | GPU |
| --- | --- | --- | --- |
| Inference, CPU (`laya.load` / `Router(preload=True)`) | any x86-64 | ~1.5 GB free | none; 193–464 ms/request |
| Inference, GPU | any | ~1.5 GB | ≥2 GB VRAM (your 4 GB is plenty) |
| Fine-tuning, head-only or LoRA (your machine) | i7 fine | ~8 GB | ≥4 GB with gradient checkpointing, micro-batch 1–2 |
| Fine-tuning, full RLCD as in the official notebook | — | — | 2×T4 (16 GB each); **Kaggle gives this free**, run takes 4–6 min |

### 2.4 Troubleshooting

**`laya.load()` hangs at import.** `transformers` probes for TensorFlow; when TF
is installed, its abseil runtime can deadlock model construction. Run with
`USE_TF=0` (or uninstall TF from the venv).

**OOM on limited GPU.** Laya inference on 4 GB should not OOM (1.5 GB total). If
fine-tuning OOMs: enable gradient checkpointing (the official script sets
`cfg["gradient_checkpointing"] = True` and
`model.encoder.gradient_checkpointing_enable(use_reentrant=False)` plus
`model.head_checkpointing = True`), drop micro-batch to 1–2, lower `max_len` to
512, and set `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` (the notebook
sets this). Fallback: run on CPU — slow but works for tiny runs.

**Context window limits.** Each question splits the budget: `head_max_len` for
the option prompt + `max_len − head_max_len` for the state. Defaults: `laya`
(English) 512 total = 192 option + ~320 state; multilingual/typed-decisions 1024
= 256 option + ~768 state. Long specs get silently truncated — the model stays
confident on the truncated view. Fixes: raise `agent.cfg["head_max_len"] = 512`
and `max_len` to 1024–8192 (multilingual encoder supports 8192 via RoPE); or
chunk the state and ask per-chunk questions; or use hierarchical choice for big
option sets.

**Router reload storms.** Default `max_loaded=1` rebuilds a model on every
language switch (7–10 s). Always `Router(preload=True)` for anything serving
requests.

**Router reports the wrong checkpoint.** Script detection is <0.5 ms pure Python
and runs *before* the forward pass — trust it over confidence gating; the English
checkpoint's confidence never drops below 0.885 even at 0.000 accuracy, so
thresholds cannot catch misrouting.

---

## 3. Integration with OpenCode

Laya's question schema matches TypeSafe Jev's primitives (`choice`/`score`/
`noul`) — the patterns already worked out in `Integrating Jev into OpenCode.txt`
carry over as a swap, not a rewrite. Difference: Jev is a closed API; Laya runs
as a **local sidecar** (the FastAPI server from §2.2) that an OpenCode plugin
calls over HTTP.

```
[ User prompt / spec ]
        |
        v
[ Input structurer ] ---> intent_manifest JSON (action, scope, criteria, non_goals)
        |
        v
[ Laya pre-execution gate ]  (one forward pass, all questions at once)
    choice: change_type          --->
    noul:   scope_unambiguous    ---| p < 0.92 --> HALT, ask user to clarify
    noul:   non_goals_violated   ---|
        | p >= 0.92
        v
[ Lock manifest ] --> OpenCode System-2 loop (big-pickle / muse / nemotron ...)
        |
        v  every tool call
[ plugin: tool.execute.before ] --> Laya: "aligns_with_intent?" (noul)
        |--- p < 0.95 --> BLOCK tool call (intent drift)
        |--- p >= 0.95 -> run tool
        v
[ Laya post-hoc ] --> trace observability questions on the session log
```

### 3.1 SPDD (Structured Plan-Driven Development)

Two existing pieces plug together:

1. **OpenSpec = the typed-artifact layer.** The `openspec-propose` workflow
   produces `proposal.md` (what & why), `specs/<capability>/spec.md` (behaviour
   deltas), `design.md` (how), `tasks.md` (steps) — and **stops**. The
   user-review-then-apply boundary *is* the verification layer: plans cannot
   reach code without explicit human sign-off, which is exactly the "middle
   layer between human communication and machine execution" you described.
2. **Laya = the probability layer around it.** Replace Gemini's `JevClient`
   calls from the Jev notes with calls to your local Laya sidecar:

```python
res = requests.post("http://localhost:8321/predict", json={
  "state": {
    "intent_manifest": manifest,          # action, target_scope, acceptance_criteria, non_goals
    "proposed_artifact": proposal_md,     # the openspec artifact under review
  },
  "questions": {
    "artifact_matches_intent": {"type": "noul",
      "instructions": "Does `proposed_artifact` stay within `intent_manifest.target_scope` and violate none of `intent_manifest.non_goals`?"},
    "criteria_covered": {"type": "score",
      "instructions": "How completely does `proposed_artifact` address every item in `intent_manifest.acceptance_criteria`?",
      "criteria": ["unaddressed", "partial", "mostly", "fully addressed"]},
    "spec_category": {"type": "choice",
      "instructions": "Which capability does this spec belong under?",
      "criteria": {"user-auth": "...", "storage": "...", "tooling": "...", "new-capability": "..."}},
  },
})
```

Suggested gates (tune on your own data, then **refit temperatures** — §4.3):

| Gate | Question | Threshold |
| --- | --- | --- |
| Intent capture | `scope_unambiguous` (noul) | ≥ 0.92 else CLARIFY_WITH_USER |
| Artifact ↔ intent | `artifact_matches_intent` (noul) | ≥ 0.90 else revise before apply |
| Task drift | `task_matches_spec` (noul) on each task row | ≥ 0.90 |
| Execution drift | `aligns_with_intent` (noul) on every `tool.execute.before` | < 0.95 → block |

Verify the exact plugin hook names against the current OpenCode plugin docs
(`tool.execute.before` / `session.start` per the Jev notes) before building.

### 3.2 Code / generic reviewer

Build verifier **question banks**; each is a dict of questions + one state.
Compose banks from:

- **Official docs**: OWASP Top 10 → one `noul` per category ("Does the described
  flow expose A01 broken access control?"); GDPR articles; protocol specs.
- **Project artifacts**: `openspec/` specs, code standards, system design docs →
  conformance `choice`/`noul` questions.
- **Agent-flow conformance**: feed the session trace as state; ask whether each
  step follows the active instructions/skills (the `agent_trace_observability`
  workflow Laya was fine-tuned for — 0.730 on held-out cases).

Keep each question a *one-second judgment* (per TypeSafe's own guidance):
"Does this error response leak stack traces?" — not "review this code for
security issues". Ask all questions in one call; Laya answers them in a single
forward pass. Combine/weight answers in code.

Hard limit: 512–1024 token state. A reviewer bank sees **conformance checks over
chunks**, not whole-repo reasoning. Deep review stays with the generative model;
Laya gates and summarises.

### 3.3 Analysis pipeline

One state → one bank → one JSON result, for any analysis domain:

```python
BANKS = {
  "market":  {"stage": score("idea/early/growth/mature"),
              "differentiator": noul("Does the pitch state a concrete differentiator?"),
              "buy_signal": choice(["none","weak","strong"])},
  "security":{"authz_risk": noul("Does the flow allow access without an authz check?"),
              "secret_exposure": noul("Are secrets written to logs or responses?"),
              "severity": score(["info","low","medium","high","critical"])},
  "content": {"tone": score(["neutral","frustrated","angry"]),
              "action_requested": choice(["none","refund","escalation","information"])},
}
```

Unified findings format — store one row per (source, bank, question):

```json
{"ts":"...","source":"spec:auth-v2","bank":"security","question":"authz_risk",
 "type":"noul","value":0.87,"model":"laya","temperature_fit":"2026-09-22"}
```

Because Laya answers 10–50 questions in a single 70–160 ms pass, run every bank
on every document — speculative fan-out is nearly free, and your code ignores
what it doesn't need.

### 3.4 Model router

Route *between* models — Laya included — with a Laya `choice` + `score` call:

| Decision | Question type | Example criteria |
| --- | --- | --- |
| Task domain | `choice` | code / data / docs / ops / out-of-scope |
| Reasoning depth needed | `score` | lookup → judgment → multi-step reasoning |
| Latency budget | `choice` | interactive / batch |
| Sensitivity | `noul` | does the state contain PII or credentials? |

Routing rules (starting point):

- **depth = lookup/judgment** → Laya directly (or another System-1 model). No
  generative call at all.
- **depth = multi-step reasoning** → generative model by domain (code →
  big-pickle; general → muse/nemotron; already-allowed free models per this
  repo's allow-list).
- **sensitivity = yes** → local-only models (Laya sidecar, local checkpoints);
  never ship the state to a hosted API.
- **language non-English** → `laya-multilingual` checkpoint (or Laya's own
  built-in script router handles this for free).
- **>20 options** → Jev API, or hierarchical two-step choice in Laya.

Laya's internal Router is itself the proof this pattern works: script detection
in <0.5 ms, then a per-input checkpoint decision with a human-readable `reason`
field — copy that shape for your own router's audit trail.

---

## 4. Fine-Tuning Guidance

Reference implementation: [notebooks/laya_finetune_typed_decisions_2xT4_kaggle.ipynb](https://github.com/NandhaKishorM/laya/blob/main/notebooks/laya_finetune_typed_decisions_2xT4_kaggle.ipynb) — full-RLCD, 2×T4, **4–6 minutes**.

### 4.1 Data preparation

**Format** (from the notebook, against `LocalLLaMA/typed-decisions`): one case =
`{id, workflow, state, questions, gold}` where `state`/`questions`/`gold` are
JSON strings. `gold` carries, per question, the full target *probability
distribution* (not just the label): `choice` → probabilities per option key;
`noul` → `{false, true}`; `score` → probabilities per level index.

The notebook's `build_training_item` then: normalises the target to sum to 1,
derives the argmax label, tokenises state+question via `laya.common.build_sequence`
(which places the option markers), and asserts marker count == option count.

**Soft targets matter.** You are training a calibrated distribution, not a
classifier — if you only have hard labels, one-hot targets work (the reward's
spherical component still shapes the distribution), but teacher-generated soft
distributions train better (that's how the reference checkpoint was made).

**How much data:** the reference fine-tune used **1,200 training cases → 6,000
decisions** and beat the teacher's self-agreement ceiling. Rule of thumb: a few
hundred labelled cases per workflow to specialise; 1,000+ to generalise across
workflows. This is the practical win of a 421M model — data needs are small.

**Augmentation:**
- **Option-order shuffling** — the authors flag option-order robustness as a
  weakness; shuffle `criteria` order per epoch.
- Paraphrase `instructions` (cheap, keeps state fixed).
- Negatives: add explicit `other`/`none_of_these` options with their own examples.
- Keep `state` as structured JSON with explicit keys — the models score paths
  like `` `ticket.messages[0].text` `` far better than free prose.

### 4.2 Training procedure

**Full FT vs LoRA vs QLoRA on 421M:**

| Method | VRAM | Fits 4 GB? | Notes |
| --- | --- | --- | --- |
| Full RLCD (official path) | ~6–7 GB | No | Run on Kaggle 2×T4 — free, 4–6 min, notebook is ready |
| Head-only + frozen encoder | ~1.5 GB | **Yes** | Train the 2-layer decision head (~26M params); fastest local option |
| LoRA on encoder + full head | ~2.5–3 GB | **Yes** | PEFT on `model.encoder` submodule + full head LR |
| QLoRA (4-bit base) | ~1.5–2 GB | **Yes** | Only if you also want encoder adaptation at minimum VRAM; adds bnb complexity for marginal gain at this size |

Honestly: at 421M on a 4 GB card, the lazy path is **head-only locally for
experiments, Kaggle 2×T4 for the real run**.

**Hyperparameters — straight from the official script:**

| Parameter | Value |
| --- | --- |
| Epochs | 4 |
| Micro-batch | 8 sequences/GPU (drop to 1–2 on 4 GB) |
| Gradient accumulation | 4 (effective 64 across 2 GPUs) |
| GRPO group size | 4 baseline samples |
| LR encoder / head | 2.5e-5 / 1.0e-4 (separate param groups) |
| Schedule | Cosine, eta_min 1e-6 |
| Exploration sigma | 0.4 → 0.1 linear over epochs |
| Weight decay / grad clip | 0.01 / 1.0 |
| Precision | fp16 autocast + GradScaler |
| Memory | gradient checkpointing (encoder, use_reentrant=False) + head checkpointing; `max_tokens_per_batch` 4096; `max_len` 1024, `head_max_len` 256 |
| Loss | GRPO policy gradient (proper reward: w_sph 0.75, w_rps 1.0) + 1.0 × soft cross-entropy guidance |
| Checkpointing | single rolling `checkpoint_latest` per epoch (crash-safe) |

**Mandatory post-training step:** per-question-type temperature calibration —
LBFGS fit of one temperature for each of choice/score/noul on held-out logits
(the notebook fits on `all_items[::15][:400]`), written into
`rl_agent_config.json["temperature"]`. Skipping this ships an over-confident
model (ECE 0.213 raw vs 0.081 refit on the reference checkpoint).

### 4.3 Validation

Evaluate on the held-out split (the notebook: 400 cases / 2,000 decisions), never
the training mix:

| Metric | What it tells you | Target |
| --- | --- | --- |
| Argmax accuracy | is the top answer right | beat the majority-class baseline (0.461 on typed-decisions) |
| Soft accuracy | overlap with the true distribution | higher = better calibration-quality training |
| Brier / KL / total variation | distribution distance | lower = better |
| **ECE** | are the probabilities honest | < 0.15 after temperature fit |
| score MAE / within-1-level | ordinal quality | lower / higher |
| Latency p50/p95 | serving sanity | ~35 ms p50 on T4-class GPU |

**Overfitting prevention:** 4 epochs only; shuffle per epoch with seeded RNG;
rolling checkpoint + per-epoch sanity eval; watch the train/test accuracy gap —
the base checkpoints scoring 0.36 on a benchmark whose fine-tune scores 0.766 is
the cautionary tale in both directions (zero-shot ≠ fine-tuned). Also eval on
*one held-out workflow* you didn't train on, to detect benchmark-specific
memorisation (the authors report guardrails 0.708–0.762 held-out vs spam 0.993
in-training — a ~0.2 drop from "seen the distribution" is normal; a collapse to
majority-class means you memorised).

---

## 5. Hardware Feasibility — i7 / 16 GB RAM / RTX 3050 Ti 4 GB

### 5.1 What is possible

| Task | Feasible? | How |
| --- | --- | --- |
| Inference, GPU | **Yes, comfortably** | fp16 421M ≈ 0.84 GB + activations < 1.5 GB total; expect ~40–80 ms/question |
| Inference, CPU | **Yes** | 193–464 ms/request; fine for prototype gates |
| Head-only fine-tune | **Yes** | ~1.5 GB; the fastest way to learn the training loop locally |
| LoRA / QLoRA | **Yes** | ~2.5–3 GB with gradient checkpointing, micro-batch 1–2, `max_len` 512 |
| Full RLCD fine-tune | **No** | AdamW states alone ≈ 5 GB. Use Kaggle 2×T4 (free, 4–6 min run) |
| 800M target | **Cap at 421M** | 800M is not a Laya size — the checkpoints are 322M / 421M. QLoRA on 800M would *just* fit but crawl; there is no 800M Laya to fine-tune toward |

### 5.2 Workarounds & alternatives

- **Gradient checkpointing** is already wired into the official script
  (`use_reentrant=False` on the encoder + `head_checkpointing = True`); it trades
  ~30% extra compute for the activation memory that would otherwise blow 4 GB.
- **CPU↔GPU offloading**: fine for inference (`device_map="auto"` style), poor
  for training — per-step transfers dominate. On this model, "CPU training" is
  only worth it for head-only runs.
- **The real workaround is Kaggle**: the official notebook is built for free 2×T4
  with internet on; checkpoint resumption (`checkpoint_latest`) already handles
  session timeouts. Train there, download the ~800 MB artifact, serve locally.

### 5.3 Verdict

**Feasible for everything except full-parameter training.** Your stated priorities
(accuracy > speed, immediate prototype, experimental, learning-focused) map to:

1. **Today:** local inference + the §3.1 gate prototype on CPU/GPU.
2. **This week:** run the Kaggle notebook as-is → you get a fine-tuned checkpoint,
   the full RLCD loop to read, and the calibration step to replicate.
3. **Then:** local head-only / LoRA experiments on your 4 GB card; keep full runs
   on Kaggle. Cap the parameter target at 421M.

---

## 6. Sources

- Model card: https://huggingface.co/convaiinnovations/laya (three checkpoints, Router, benchmarks, honest limits)
- BENCHMARKS.md: https://github.com/NandhaKishorM/laya/blob/main/BENCHMARKS.md (51-language sweep, typed-decisions, calibration, option-order robustness)
- Fine-tuning notebook: https://github.com/NandhaKishorM/laya/blob/main/notebooks/laya_finetune_typed_decisions_2xT4_kaggle.ipynb (all hyperparameters in §4.2 come from its `train_ddp.py`)
- Dataset: https://huggingface.co/datasets/LocalLLaMA/typed-decisions
- PyPI: https://pypi.org/project/laya/
- Jev benchmarks (third-party): https://github.com/AbdelStark/jev-benchmarks, https://github.com/nibzard/decision-model-benchmark
- TypeSafe primitives (Choice/Score/Noul semantics): https://docs.typesafe.ai/primitives.md
- This repo: `Integrating Jev into OpenCode.txt` (intent-manifest sandwich pattern), `README.md` (OpenCode model allow-list incl. `jev-1.13-free`), `~/.agents/skills/openspec-*` (typed planning artifacts)
- llama.cpp supported models: https://github.com/ggml-org/llama.cpp (BERT PR #5423; no ModernBERT decision-head support)
