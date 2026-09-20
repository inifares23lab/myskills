# myskills

Aggregates the skills this machine should have, across Claude Code, Codex and
OpenCode.

```sh
./install.sh
```

Each skill is a standalone tool with its own repo and its own way of installing.
There is no contract for them to satisfy. This repo is the list of them, plus
whatever each one needs on top of its own installer — a new skill gets a new
block in `install.sh`, shaped however that skill happens to work.

No agent-facing markdown lives here. Where something has to be written into a
tool's config, it is pulled from the skill's own source at install time.

## Where skills live

One plain copy of each non-plugin skill, in `~/.agents/skills` — the generic
home that both Codex (USER scope) and OpenCode read. Claude reads only its own
directory, so it keeps a copy in `~/.claude/skills`; that dir is claude-specific
and never duplicates work: OpenCode dedupes by name and reads it too.

Skills that ship as plugins (ponytail, i-have-adhd, typesafe-ai) have no plain
copy anywhere — the plugin is the copy, and OpenCode loads skills bundled with
its plugins, npm or path. `~/.codex/skills` and `~/.opencode/skills` are legacy:
no current tool reads them, and `install.sh` clears its skills out.

| Location           | Read by                    | Gets                                                     |
| ------------------ | -------------------------- | -------------------------------------------------------- |
| `~/.agents/skills` | codex, opencode            | learn, visual, visual-explainer, openspec-*, typesafe-ai |
| `~/.claude/skills` | claude (opencode dedupes)  | same set as `~/.agents/skills`                           |
| plugins            | per-tool                   | ponytail (+ its five sub-skills), i-have-adhd, typesafe-ai |


| Skill       | Default   | Comes from                       | Extra here                     |
| ----------- | --------- | -------------------------------- | ------------------------------ |
| ponytail    | always on | `DietrichGebert/ponytail` plugin, `@dietrichgebert/ponytail` on npm for opencode | none — hooks itself |
| i-have-adhd | always on | `ayghri/i-have-adhd` plugin      | flag files only                 |
| learn       | on demand | `learnkit` repo                  | always-on plugin               |
| visual      | on demand | `visual-docs` repo               | always-on plugin               |
| visual-explainer | on demand | `nicobailon/visual-explainer` plugin | none — the tree is the skill   |
| openspec         | on demand | `@fission-ai/openspec` on npm        | global skills + commands, generated once |

`learnkit` and `visual-docs` are cloned shallow into a temp dir, run, and thrown
away. A repo that will not clone fails by name and the rest still install.

## How each one is always on

Both always-on skills bring their own mechanism. Nothing here hand-rolls one,
and `~/.claude/CLAUDE.md` is never touched.

**ponytail** — its plugin registers a `SessionStart` hook that injects the
ruleset. Install it and it is on.

**i-have-adhd** — upstream ships two independent always-on mechanisms, each
gated on its own flag file, so the install is the plugin plus a `touch`. A
Claude Code `SessionStart` hook ([`hooks/hooks.json`], [`hooks/always-on.mjs`])
reads `~/.claude/.i-have-adhd-always`; an OpenCode server plugin
([`.opencode/plugins/i-have-adhd.mjs`]) reads
`~/.config/opencode/.i-have-adhd-always`. Both documented in upstream's
[`INSTALL.md`] under "Always-on (optional)".

[`hooks/hooks.json`]: https://github.com/ayghri/i-have-adhd/blob/main/hooks/hooks.json
[`hooks/always-on.mjs`]: https://github.com/ayghri/i-have-adhd/blob/main/hooks/always-on.mjs
[`.opencode/plugins/i-have-adhd.mjs`]: https://github.com/ayghri/i-have-adhd/blob/main/.opencode/plugins/i-have-adhd.mjs
[`INSTALL.md`]: https://github.com/ayghri/i-have-adhd/blob/main/INSTALL.md

| Tool        | Mechanism                                              |
| ----------- | ------------------------------------------------------ |
| Claude Code | plugin + `~/.claude/.i-have-adhd-always`               |
| OpenCode    | vendored plugin + `~/.config/opencode/.i-have-adhd-always` |
| Codex       | plugin, whose bundled `SessionStart` hook reads the same `~/.claude/.i-have-adhd-always` |

Codex's plugin ships `hooks/hooks.json`, so all three get the always-on ruleset
from upstream's own mechanisms. An earlier layout pasted the `SKILL.md` body
into a `<!-- myskills:i-have-adhd -->` region of `~/.codex/AGENTS.md`; the
plugin hook made that redundant, and `install.sh` deletes the stale region.

OpenCode is also the one exception to throwaway clones — it loads a plugin from
a path, so that checkout persists at `~/.config/opencode/vendor/i-have-adhd` and
is `git pull`ed on re-runs. ponytail needs no checkout: opencode installs the
npm package itself.

**Codex needs one manual step per hooking plugin.** Codex will not run a
plugin's hooks until they are trusted. Open `codex`, run `/hooks`, trust
ponytail's two and i-have-adhd's one. Until then Codex has the skills but not
the always-on injection.

Verified with a fresh session per tool — Codex answers `ponytail, i-have-adhd`;
Claude Code and OpenCode add `learn, visual`, whose descriptions they surface
without loading:

```sh
claude -p --model haiku 'name the skills in your context'
codex exec --skip-git-repo-check 'name the skills in your context'
opencode run 'name the skills in your context'
```

`openspec` is the one skill generated rather than installed: `openspec init` in
a throwaway project produces the skill and command trees, copied into
`~/.agents/skills` and `~/.claude/skills` — so every session sees `/opsx:*`.
The specs and changes themselves stay per project: `openspec init` in a repo
writes only that repo's `openspec/` directory.

## Switches

Independent, so turning one off leaves the others running.

| Skill       | Off              | On                            |
| ----------- | ---------------- | ----------------------------- |
| i-have-adhd | `stop adhd mode` | `adhd mode` or `/i-have-adhd` |
| ponytail    | `stop ponytail`  | `/ponytail lite\|full\|ultra` |
| learn       | `stop learn mode` | `/learn` or `learn mode`     |
| visual      | `no diagrams`    | `/visual` or `diagrams on`    |

Conversational — they last the session. Each of learn and visual has one more
state: `learn always` / `visual always` touches
`~/.config/opencode/.learn-always` / `.visual-always`, and its plugin injects
the full body into every new session while the file exists; `learn never` /
`visual never` removes it. To turn i-have-adhd off for good, delete its flag
file rather than saying it every session — learn and visual are the same, plus
the conversational switch.

## Model allow-list (OpenCode v2)

OpenCode v2 ignores the V1 `provider.opencode.whitelist` shape (accepted but
unsupported — see the v2 migration guide). V2 has no allow-list field; a model
is hidden with `providers.<id>.models.<model>.disabled: true`. The blocks below
replace the old whitelist in `~/.config/opencode/opencode.json`, disabling
every catalog model except the kept sets (snapshot: opencode 74 catalog models,
openrouter 371). New catalog models appear enabled until added to the list.

Kept — opencode (7, the same values as the old whitelist):

```
big-pickle
jev-1.13-free
muse-spark-1.3-contributor-free
nemotron-3.5-lightning-free
nemotron-3-ultra-free
ling-3.0-flash-fin-free
mimo-v2.5-free
```

Kept — openrouter ($0 models, 28; includes OpenRouter's $0 gateway models
`auto`, `free`, `bodybuilder`, `fusion`, `pareto-code` — drop those if unwanted):

```
openrouter/cohere/north-mini-code:free
openrouter/dots-studio/dots-3-note-preview:free
openrouter/google/gemma-4-26b-a4b-it:free
openrouter/google/gemma-4-31b-it:free
openrouter/google/lyria-3-clip-preview
openrouter/google/lyria-3-pro-preview
openrouter/inclusionai/ling-3.0-flash-fin:free
openrouter/inclusionai/ling-3.0-flash-sante:free
openrouter/inclusionai/ling-3.0-flash-vl:free
openrouter/liquid/lfm-2.5-2.6b:free
openrouter/nex-agi/nex-n2.5-mini:free
openrouter/nex-agi/nex-n2.5-pro:free
openrouter/nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free
openrouter/nvidia/nemotron-3-super-120b-a12b:free
openrouter/nvidia/nemotron-3-ultra-550b-a55b:free
openrouter/nvidia/nemotron-3.5-content-safety:free
openrouter/nvidia/nemotron-3.5-lightning:free
openrouter/openrouter/auto
openrouter/openrouter/bodybuilder
openrouter/openrouter/free
openrouter/openrouter/fusion
openrouter/openrouter/pareto-code
openrouter/poolside/laguna-s-2.1:free
openrouter/poolside/laguna-xs-2.1:free
openrouter/qwen/qwen3.8-27b:free
openrouter/thinkingmachines/inkling-small:free
openrouter/thinkingmachines/inkling:free
openrouter/z-ai/glm-5.2:free
```

`jev latest` is not on openrouter (checked the whole catalog). It exists on the
opencode provider as `opencode/jev-latest` but is paid, so it is not in the
opencode keep-list; to allow it, remove its `"disabled": true` entry.

Kept — zai (2):

```
glm-5.3-flash
glm-4.7-flash
```

Kept — deepseek (2):

```
deepseek-flash
deepseek-v4-pro
```

Blocklist keys are model IDs **without** the provider prefix —
`providers.openrouter.models` is keyed `z-ai/glm-5.2`, not
`openrouter/z-ai/glm-5.2`. Prefixed keys match nothing and silently disable
nothing (the bug this config shipped with once).

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "enabled_providers": [
    "deepseek",
    "zai",
    "opencode",
    "openrouter"
  ],
  "providers": {
    "zai": {
      "models": {
        "glm-4.5": {
          "disabled": true
        },
        "glm-4.5-air": {
          "disabled": true
        },
        "glm-4.5-flash": {
          "disabled": true
        },
        "glm-4.5v": {
          "disabled": true
        },
        "glm-4.6": {
          "disabled": true
        },
        "glm-4.6v": {
          "disabled": true
        },
        "glm-4.7": {
          "disabled": true
        },
        "glm-4.7-flash": {
          "disabled": false
        },
        "glm-4.7-flashx": {
          "disabled": true
        },
        "glm-5": {
          "disabled": true
        },
        "glm-5-turbo": {
          "disabled": true
        },
        "glm-5.1": {
          "disabled": true
        },
        "glm-5.2": {
          "disabled": true
        },
        "glm-5.3": {
          "disabled": true
        },
        "glm-5.3-flashx": {
          "disabled": true
        },
        "glm-5v-turbo": {
          "disabled": true
        }
      }
    },
    "opencode": {
      "models": {
        "jev-1.13": {
          "disabled": true
        },
        "jev-latest": {
          "disabled": false
        },
        "deepseek-v4.1-flash": {
          "disabled": true
        },
        "gpt-6-astra": {
          "disabled": true
        },
        "muse-spark-1.3": {
          "disabled": true
        },
        "gemini-3.8-flash": {
          "disabled": true
        },
        "claude-fable-5-1": {
          "disabled": true
        },
        "glm-5.3-flash": {
          "disabled": true
        },
        "qwen3.8-flash": {
          "disabled": true
        },
        "deepseek-v4-flash-vision-exp": {
          "disabled": true
        },
        "glm-5.3": {
          "disabled": true
        },
        "gemini-3.7-flash": {
          "disabled": true
        },
        "grok-4.6": {
          "disabled": true
        },
        "muse-spark-1.2": {
          "disabled": true
        },
        "muse-spark-1.2-contributor-free": {
          "disabled": true
        },
        "deepseek-v4-flash": {
          "disabled": true
        },
        "claude-opus-5": {
          "disabled": true
        },
        "gemini-3.6-flash": {
          "disabled": true
        },
        "gemini-3.5-flash-lite": {
          "disabled": true
        },
        "kimi-k3": {
          "disabled": true
        },
        "gpt-5.6-sol": {
          "disabled": true
        },
        "gpt-5.6-luna": {
          "disabled": true
        },
        "gpt-5.6-terra": {
          "disabled": true
        },
        "grok-4.5": {
          "disabled": true
        },
        "claude-sonnet-5": {
          "disabled": true
        },
        "glm-5.2": {
          "disabled": true
        },
        "kimi-k2.7-code": {
          "disabled": true
        },
        "claude-fable-5": {
          "disabled": true
        },
        "minimax-m3": {
          "disabled": true
        },
        "claude-opus-4-8": {
          "disabled": true
        },
        "gemini-3.5-flash": {
          "disabled": true
        },
        "gpt-5.5-pro": {
          "disabled": true
        },
        "deepseek-v4-pro": {
          "disabled": true
        },
        "gpt-5.5": {
          "disabled": true
        },
        "kimi-k2.6": {
          "disabled": true
        },
        "grok-build-0.1": {
          "disabled": true
        },
        "claude-opus-4-7": {
          "disabled": true
        },
        "glm-5.1": {
          "disabled": true
        },
        "qwen3.6-plus": {
          "disabled": true
        },
        "minimax-m2.7": {
          "disabled": true
        },
        "gpt-5.4-nano": {
          "disabled": true
        },
        "gpt-5.4-mini": {
          "disabled": true
        },
        "gpt-5.4": {
          "disabled": true
        },
        "gpt-5.4-pro": {
          "disabled": true
        },
        "gpt-5.3-codex": {
          "disabled": true
        },
        "gemini-3.1-pro": {
          "disabled": true
        },
        "claude-sonnet-4-6": {
          "disabled": true
        },
        "qwen3.5-plus": {
          "disabled": true
        },
        "minimax-m2.5": {
          "disabled": true
        },
        "gpt-5.3-codex-spark": {
          "disabled": true
        },
        "glm-5": {
          "disabled": true
        },
        "claude-opus-4-6": {
          "disabled": true
        },
        "kimi-k2.5": {
          "disabled": true
        },
        "gpt-5.2-codex": {
          "disabled": true
        },
        "gemini-3-flash": {
          "disabled": true
        },
        "gpt-5.2": {
          "disabled": true
        },
        "claude-opus-4-5": {
          "disabled": true
        },
        "gpt-5.1-codex-mini": {
          "disabled": true
        },
        "gpt-5.1-codex": {
          "disabled": true
        },
        "gpt-5.1": {
          "disabled": true
        },
        "gpt-5.1-codex-max": {
          "disabled": true
        },
        "claude-haiku-4-5": {
          "disabled": true
        },
        "claude-sonnet-4-5": {
          "disabled": true
        },
        "gpt-5-codex": {
          "disabled": true
        },
        "gpt-5-nano": {
          "disabled": true
        },
        "gpt-5": {
          "disabled": true
        },
        "claude-sonnet-4": {
          "disabled": true
        }
      }
    },
    "openrouter": {
      "models": {
        "prism-ml/ternary-bonsai-2-27b": {
          "disabled": true
        },
        "z-ai/glm-5.3-flashx": {
          "disabled": true
        },
        "unbiased/pareto": {
          "disabled": true
        },
        "~deepseek/deepseek-pro-latest": {
          "disabled": true
        },
        "~deepseek/deepseek-flash-latest": {
          "disabled": true
        },
        "inference-net/schematron-v2-small": {
          "disabled": true
        },
        "inference-net/schematron-v2-turbo": {
          "disabled": true
        },
        "sakana/fugu-max": {
          "disabled": true
        },
        "sakana/fugu-ultra-v2": {
          "disabled": true
        },
        "~openai/gpt-terra-latest": {
          "disabled": true
        },
        "~openai/gpt-sol-latest": {
          "disabled": true
        },
        "~openai/gpt-luna-latest": {
          "disabled": true
        },
        "~openai/gpt-astra-latest": {
          "disabled": true
        },
        "deepseek/deepseek-v4.1-flash": {
          "disabled": true
        },
        "inclusionai/ling-3.0-flash-vl": {
          "disabled": true
        },
        "inception/mercury-2.5": {
          "disabled": true
        },
        "openai/gpt-6-astra-pro": {
          "disabled": true
        },
        "openai/gpt-6-astra": {
          "disabled": true
        },
        "qwen/qwen3.8-max-0902": {
          "disabled": true
        },
        "google/gemini-3.8-flash": {
          "disabled": true
        },
        "meta/muse-spark-1.3": {
          "disabled": true
        },
        "meta/muse-spark-1.3-contributor": {
          "disabled": true
        },
        "anthropic/claude-fable-5.1": {
          "disabled": true
        },
        "ibm-granite/granite-4.2-8b": {
          "disabled": true
        },
        "tencent/hy4-preview": {
          "disabled": true
        },
        "inclusionai/ling-3.0-flash-fin": {
          "disabled": true
        },
        "~z-ai/glm-flash-latest": {
          "disabled": true
        },
        "qwen/qwen3.8-flash": {
          "disabled": true
        },
        "z-ai/glm-5.3-flash": {
          "disabled": true
        },
        "meta/muse-spark-1.2-contributor": {
          "disabled": true
        },
        "deepseek/deepseek-v4-flash-vision-exp": {
          "disabled": true
        },
        "tencent/hy-mt2-30b-a3b": {
          "disabled": true
        },
        "tencent/hy-mt2-1.8b": {
          "disabled": true
        },
        "~z-ai/glm-latest": {
          "disabled": true
        },
        "tencent/hy-mt2-7b": {
          "disabled": true
        },
        "qwen/qwen3.8-27b": {
          "disabled": true
        },
        "z-ai/glm-5.3": {
          "disabled": true
        },
        "google/gemini-3.7-flash": {
          "disabled": true
        },
        "qwen/qwen3.8-2.4t-a95b": {
          "disabled": true
        },
        "bytedance-seed/seed-2-1-turbo": {
          "disabled": true
        },
        "deepseek/deepseek-v4-pro-0813": {
          "disabled": true
        },
        "x-ai/grok-4.6": {
          "disabled": true
        },
        "nvidia/nemotron-3.5-lightning": {
          "disabled": true
        },
        "meta/muse-glimmer-30b": {
          "disabled": true
        },
        "upstage/solar-pro4": {
          "disabled": true
        },
        "meta/muse-spark-1.2": {
          "disabled": true
        },
        "sakana/sakana-namazu": {
          "disabled": true
        },
        "~deepseek/deepseek-v4-flash-latest": {
          "disabled": true
        },
        "deepseek/deepseek-v4-flash-0731": {
          "disabled": true
        },
        "thinkingmachines/inkling-small": {
          "disabled": true
        },
        "anthropic/claude-opus-5": {
          "disabled": true
        },
        "inclusionai/ling-3.0-flash": {
          "disabled": true
        },
        "poolside/laguna-s-2.1": {
          "disabled": true
        },
        "google/gemini-3.6-flash": {
          "disabled": true
        },
        "google/gemini-3.5-flash-lite": {
          "disabled": true
        },
        "meituan/longcat-2.0": {
          "disabled": true
        },
        "moonshotai/kimi-k3": {
          "disabled": true
        },
        "qwen/qwen3.7-flash": {
          "disabled": true
        },
        "thinkingmachines/inkling": {
          "disabled": true
        },
        "kwaipilot/kat-coder-pro-v2.5": {
          "disabled": true
        },
        "openai/gpt-5.6-sol": {
          "disabled": true
        },
        "openai/gpt-5.6-luna-pro": {
          "disabled": true
        },
        "openai/gpt-5.6-sol-pro": {
          "disabled": true
        },
        "openai/gpt-5.6-luna": {
          "disabled": true
        },
        "openai/gpt-5.6-terra-pro": {
          "disabled": true
        },
        "openai/gpt-5.6-terra": {
          "disabled": true
        },
        "~x-ai/grok-latest": {
          "disabled": true
        },
        "x-ai/grok-4.5": {
          "disabled": true
        },
        "aion-labs/aion-3.0": {
          "disabled": true
        },
        "aion-labs/aion-3.0-mini": {
          "disabled": true
        },
        "tencent/hy3": {
          "disabled": true
        },
        "poolside/laguna-xs-2.1": {
          "disabled": true
        },
        "anthropic/claude-sonnet-5": {
          "disabled": true
        },
        "google/gemini-3.1-flash-lite-image": {
          "disabled": true
        },
        "sakana/fugu-ultra": {
          "disabled": true
        },
        "z-ai/glm-5.2": {
          "disabled": true
        },
        "moonshotai/kimi-k2.7-code": {
          "disabled": true
        },
        "~anthropic/claude-fable-latest": {
          "disabled": true
        },
        "anthropic/claude-fable-5": {
          "disabled": true
        },
        "nvidia/nemotron-3.5-content-safety": {
          "disabled": true
        },
        "nvidia/nemotron-3-ultra-550b-a55b": {
          "disabled": true
        },
        "qwen/qwen3.7-plus": {
          "disabled": true
        },
        "minimax/minimax-m3": {
          "disabled": true
        },
        "stepfun/step-3.7-flash": {
          "disabled": true
        },
        "anthropic/claude-opus-4.8": {
          "disabled": true
        },
        "google/gemini-3-pro-image": {
          "disabled": true
        },
        "google/gemini-3.1-flash-image": {
          "disabled": true
        },
        "qwen/qwen3.7-max": {
          "disabled": true
        },
        "google/gemini-3.5-flash": {
          "disabled": true
        },
        "perceptron/perceptron-mk1": {
          "disabled": true
        },
        "google/gemini-3.1-flash-lite": {
          "disabled": true
        },
        "openai/gpt-chat-latest": {
          "disabled": true
        },
        "mistralai/mistral-medium-3-5": {
          "disabled": true
        },
        "qwen/qwen3.5-plus-20260420": {
          "disabled": true
        },
        "qwen/qwen3.6-flash": {
          "disabled": true
        },
        "~anthropic/claude-haiku-latest": {
          "disabled": true
        },
        "~anthropic/claude-sonnet-latest": {
          "disabled": true
        },
        "~google/gemini-pro-latest": {
          "disabled": true
        },
        "~google/gemini-flash-latest": {
          "disabled": true
        },
        "~moonshotai/kimi-latest": {
          "disabled": true
        },
        "~openai/gpt-mini-latest": {
          "disabled": true
        },
        "deepseek/deepseek-v4-flash": {
          "disabled": true
        },
        "deepseek/deepseek-v4-pro": {
          "disabled": true
        },
        "openai/gpt-5.5-pro": {
          "disabled": true
        },
        "openai/gpt-5.5": {
          "disabled": true
        },
        "qwen/qwen3.6-27b": {
          "disabled": true
        },
        "xiaomi/mimo-v2.5": {
          "disabled": true
        },
        "xiaomi/mimo-v2.5-pro": {
          "disabled": true
        },
        "~anthropic/claude-opus-latest": {
          "disabled": true
        },
        "openai/gpt-5.4-image-2": {
          "disabled": true
        },
        "moonshotai/kimi-k2.6": {
          "disabled": true
        },
        "qwen/qwen3.6-max-preview": {
          "disabled": true
        },
        "tencent/hy3-preview": {
          "disabled": true
        },
        "qwen/qwen3.6-35b-a3b": {
          "disabled": true
        },
        "x-ai/grok-4.3": {
          "disabled": true
        },
        "anthropic/claude-opus-4.7": {
          "disabled": true
        },
        "x-ai/grok-build-0.1": {
          "disabled": true
        },
        "meta/muse-spark-1.1": {
          "disabled": true
        },
        "z-ai/glm-5.1": {
          "disabled": true
        },
        "qwen/qwen3.6-plus": {
          "disabled": true
        },
        "google/gemma-4-26b-a4b-it": {
          "disabled": true
        },
        "google/gemma-4-31b-it": {
          "disabled": true
        },
        "arcee-ai/trinity-large-thinking": {
          "disabled": true
        },
        "z-ai/glm-5v-turbo": {
          "disabled": true
        },
        "x-ai/grok-4.20-multi-agent": {
          "disabled": true
        },
        "x-ai/grok-4.20": {
          "disabled": true
        },
        "kwaipilot/kat-coder-pro-v2": {
          "disabled": true
        },
        "rekaai/reka-edge": {
          "disabled": true
        },
        "minimax/minimax-m2.7": {
          "disabled": true
        },
        "openai/gpt-5.4-nano": {
          "disabled": true
        },
        "openai/gpt-5.4-mini": {
          "disabled": true
        },
        "mistralai/mistral-small-2603": {
          "disabled": true
        },
        "z-ai/glm-5-turbo": {
          "disabled": true
        },
        "nvidia/nemotron-3-super-120b-a12b": {
          "disabled": true
        },
        "openai/gpt-5.4": {
          "disabled": true
        },
        "openai/gpt-5.4-pro": {
          "disabled": true
        },
        "inception/mercury-2": {
          "disabled": true
        },
        "google/gemini-3.1-flash-lite-preview": {
          "disabled": true
        },
        "google/gemini-3.1-flash-image-preview": {
          "disabled": true
        },
        "qwen/qwen3.5-flash-02-23": {
          "disabled": true
        },
        "qwen/qwen3.5-9b": {
          "disabled": true
        },
        "qwen/qwen3.5-27b": {
          "disabled": true
        },
        "qwen/qwen3.5-35b-a3b": {
          "disabled": true
        },
        "qwen/qwen3.5-122b-a10b": {
          "disabled": true
        },
        "aion-labs/aion-2.0": {
          "disabled": true
        },
        "google/gemini-3.1-pro-preview-customtools": {
          "disabled": true
        },
        "google/gemini-3.1-pro-preview": {
          "disabled": true
        },
        "anthropic/claude-sonnet-4.6": {
          "disabled": true
        },
        "qwen/qwen3.5-plus-02-15": {
          "disabled": true
        },
        "qwen/qwen3.5-397b-a17b": {
          "disabled": true
        },
        "bytedance-seed/seed-2.0-code": {
          "disabled": true
        },
        "bytedance-seed/seed-2.0-mini": {
          "disabled": true
        },
        "bytedance-seed/seed-2.0-lite": {
          "disabled": true
        },
        "minimax/minimax-m2.5": {
          "disabled": true
        },
        "z-ai/glm-5": {
          "disabled": true
        },
        "qwen/qwen3-max-thinking": {
          "disabled": true
        },
        "anthropic/claude-opus-4.6": {
          "disabled": true
        },
        "openai/gpt-5.3-codex": {
          "disabled": true
        },
        "qwen/qwen3-coder-next": {
          "disabled": true
        },
        "stepfun/step-3.5-flash": {
          "disabled": true
        },
        "upstage/solar-pro-3": {
          "disabled": true
        },
        "minimax/minimax-m2-her": {
          "disabled": true
        },
        "writer/palmyra-x5": {
          "disabled": true
        },
        "openai/gpt-audio-mini": {
          "disabled": true
        },
        "openai/gpt-audio": {
          "disabled": true
        },
        "z-ai/glm-4.7-flash": {
          "disabled": true
        },
        "moonshotai/kimi-k2.5": {
          "disabled": true
        },
        "minimax/minimax-m2.1": {
          "disabled": true
        },
        "bytedance-seed/seed-1.6-flash": {
          "disabled": true
        },
        "bytedance-seed/seed-1.6": {
          "disabled": true
        },
        "z-ai/glm-4.7": {
          "disabled": true
        },
        "google/gemini-3-flash-preview": {
          "disabled": true
        },
        "nvidia/nemotron-3-nano-30b-a3b": {
          "disabled": true
        },
        "openai/gpt-5.2-codex": {
          "disabled": true
        },
        "openai/gpt-5.2-pro": {
          "disabled": true
        },
        "openai/gpt-5.2": {
          "disabled": true
        },
        "openai/gpt-5.2-chat": {
          "disabled": true
        },
        "mistralai/devstral-2512": {
          "disabled": true
        },
        "relace/relace-search": {
          "disabled": true
        },
        "z-ai/glm-4.6v": {
          "disabled": true
        },
        "mistralai/ministral-14b-2512": {
          "disabled": true
        },
        "mistralai/ministral-3b-2512": {
          "disabled": true
        },
        "mistralai/ministral-8b-2512": {
          "disabled": true
        },
        "amazon/nova-2-lite-v1": {
          "disabled": true
        },
        "deepseek/deepseek-chat": {
          "disabled": true
        },
        "deepseek/deepseek-v3.2": {
          "disabled": true
        },
        "anthropic/claude-opus-4.5": {
          "disabled": true
        },
        "google/gemini-3-pro-image-preview": {
          "disabled": true
        },
        "openai/gpt-5.1-codex-mini": {
          "disabled": true
        },
        "openai/gpt-5.1-codex": {
          "disabled": true
        },
        "openai/gpt-5.1": {
          "disabled": true
        },
        "openai/gpt-5.1-codex-max": {
          "disabled": true
        },
        "moonshotai/kimi-k2-thinking": {
          "disabled": true
        },
        "amazon/nova-premier-v1": {
          "disabled": true
        },
        "perplexity/sonar-pro-search": {
          "disabled": true
        },
        "openai/gpt-oss-safeguard-20b": {
          "disabled": true
        },
        "minimax/minimax-m2": {
          "disabled": true
        },
        "qwen/qwen3-vl-32b-instruct": {
          "disabled": true
        },
        "ibm-granite/granite-4.0-h-micro": {
          "disabled": true
        },
        "openai/gpt-5-image-mini": {
          "disabled": true
        },
        "anthropic/claude-haiku-4.5": {
          "disabled": true
        },
        "qwen/qwen3-vl-8b-thinking": {
          "disabled": true
        },
        "qwen/qwen3-vl-8b-instruct": {
          "disabled": true
        },
        "openai/gpt-5-image": {
          "disabled": true
        },
        "qwen/qwen3-vl-30b-a3b-instruct": {
          "disabled": true
        },
        "qwen/qwen3-vl-30b-a3b-thinking": {
          "disabled": true
        },
        "openai/gpt-5-pro": {
          "disabled": true
        },
        "z-ai/glm-4.6": {
          "disabled": true
        },
        "anthropic/claude-sonnet-4.5": {
          "disabled": true
        },
        "deepseek/deepseek-v3.2-exp": {
          "disabled": true
        },
        "thedrummer/cydonia-24b-v4.1": {
          "disabled": true
        },
        "relace/relace-apply-3": {
          "disabled": true
        },
        "qwen/qwen3-max": {
          "disabled": true
        },
        "qwen/qwen3-vl-235b-a22b-thinking": {
          "disabled": true
        },
        "qwen/qwen3-vl-235b-a22b-instruct": {
          "disabled": true
        },
        "deepseek/deepseek-v3.1-terminus": {
          "disabled": true
        },
        "qwen/qwen-plus-2025-07-28": {
          "disabled": true
        },
        "moonshotai/kimi-k2-0905": {
          "disabled": true
        },
        "qwen/qwen3-next-80b-a3b-thinking": {
          "disabled": true
        },
        "qwen/qwen3-next-80b-a3b-instruct": {
          "disabled": true
        },
        "qwen/qwen3-30b-a3b-thinking-2507": {
          "disabled": true
        },
        "google/gemini-2.5-flash-image": {
          "disabled": true
        },
        "nousresearch/hermes-4-405b": {
          "disabled": true
        },
        "deepseek/deepseek-chat-v3.1": {
          "disabled": true
        },
        "mistralai/mistral-medium-3.1": {
          "disabled": true
        },
        "z-ai/glm-4.5v": {
          "disabled": true
        },
        "openai/gpt-5-nano": {
          "disabled": true
        },
        "openai/gpt-5-mini": {
          "disabled": true
        },
        "openai/gpt-5": {
          "disabled": true
        },
        "anthropic/claude-opus-4.1": {
          "disabled": true
        },
        "openai/gpt-oss-20b": {
          "disabled": true
        },
        "openai/gpt-oss-120b": {
          "disabled": true
        },
        "mistralai/codestral-2508": {
          "disabled": true
        },
        "qwen/qwen3-30b-a3b-instruct-2507": {
          "disabled": true
        },
        "qwen/qwen3-coder-flash": {
          "disabled": true
        },
        "z-ai/glm-4.5-air": {
          "disabled": true
        },
        "z-ai/glm-4.5": {
          "disabled": true
        },
        "qwen/qwen3-235b-a22b-thinking-2507": {
          "disabled": true
        },
        "qwen/qwen3-coder-plus": {
          "disabled": true
        },
        "qwen/qwen3-coder": {
          "disabled": true
        },
        "bytedance/ui-tars-1.5-7b": {
          "disabled": true
        },
        "qwen/qwen3-235b-a22b-2507": {
          "disabled": true
        },
        "mistralai/voxtral-small-24b-2507": {
          "disabled": true
        },
        "moonshotai/kimi-k2": {
          "disabled": true
        },
        "cognitivecomputations/dolphin-mistral-24b-venice-edition": {
          "disabled": true
        },
        "tencent/hunyuan-a13b-instruct": {
          "disabled": true
        },
        "morph/morph-v3-large": {
          "disabled": true
        },
        "morph/morph-v3-fast": {
          "disabled": true
        },
        "baidu/ernie-4.5-vl-424b-a47b": {
          "disabled": true
        },
        "mistralai/mistral-small-3.2-24b-instruct": {
          "disabled": true
        },
        "minimax/minimax-m1": {
          "disabled": true
        },
        "google/gemini-2.5-flash-lite": {
          "disabled": true
        },
        "google/gemini-2.5-pro": {
          "disabled": true
        },
        "google/gemini-2.5-flash": {
          "disabled": true
        },
        "openai/o3-pro": {
          "disabled": true
        },
        "google/gemini-2.5-pro-preview": {
          "disabled": true
        },
        "deepseek/deepseek-r1-0528": {
          "disabled": true
        },
        "anthropic/claude-opus-4": {
          "disabled": true
        },
        "anthropic/claude-sonnet-4": {
          "disabled": true
        },
        "mistralai/mistral-medium-3": {
          "disabled": true
        },
        "meta-llama/llama-guard-4-12b": {
          "disabled": true
        },
        "qwen/qwen3-14b": {
          "disabled": true
        },
        "qwen/qwen3-30b-a3b": {
          "disabled": true
        },
        "qwen/qwen3-8b": {
          "disabled": true
        },
        "openai/o4-mini-high": {
          "disabled": true
        },
        "openai/o4-mini": {
          "disabled": true
        },
        "openai/o3": {
          "disabled": true
        },
        "openai/gpt-4.1-nano": {
          "disabled": true
        },
        "openai/gpt-4.1-mini": {
          "disabled": true
        },
        "openai/gpt-4.1": {
          "disabled": true
        },
        "meta-llama/llama-4-maverick": {
          "disabled": true
        },
        "meta-llama/llama-4-scout": {
          "disabled": true
        },
        "qwen/qwen3-32b": {
          "disabled": true
        },
        "qwen/qwen3-coder-30b-a3b-instruct": {
          "disabled": true
        },
        "qwen/qwen3-235b-a22b": {
          "disabled": true
        },
        "deepseek/deepseek-chat-v3-0324": {
          "disabled": true
        },
        "openai/o1-pro": {
          "disabled": true
        },
        "mistralai/mistral-small-3.1-24b-instruct": {
          "disabled": true
        },
        "cohere/command-a": {
          "disabled": true
        },
        "google/gemma-3-4b-it": {
          "disabled": true
        },
        "google/gemma-3-27b-it": {
          "disabled": true
        },
        "google/gemma-3-12b-it": {
          "disabled": true
        },
        "rekaai/reka-flash-3": {
          "disabled": true
        },
        "thedrummer/skyfall-36b-v2": {
          "disabled": true
        },
        "perplexity/sonar-reasoning-pro": {
          "disabled": true
        },
        "perplexity/sonar-pro": {
          "disabled": true
        },
        "perplexity/sonar-deep-research": {
          "disabled": true
        },
        "mistralai/mistral-saba": {
          "disabled": true
        },
        "openai/o3-mini-high": {
          "disabled": true
        },
        "aion-labs/aion-rp-llama-3.1-8b": {
          "disabled": true
        },
        "qwen/qwen2.5-vl-72b-instruct": {
          "disabled": true
        },
        "mistralai/mistral-small-24b-instruct-2501": {
          "disabled": true
        },
        "perplexity/sonar": {
          "disabled": true
        },
        "deepseek/deepseek-r1-distill-llama-70b": {
          "disabled": true
        },
        "deepseek/deepseek-r1": {
          "disabled": true
        },
        "minimax/minimax-01": {
          "disabled": true
        },
        "microsoft/phi-4": {
          "disabled": true
        },
        "openai/o3-mini": {
          "disabled": true
        },
        "sao10k/l3.3-euryale-70b": {
          "disabled": true
        },
        "meta-llama/llama-3.3-70b-instruct": {
          "disabled": true
        },
        "amazon/nova-micro-v1": {
          "disabled": true
        },
        "amazon/nova-pro-v1": {
          "disabled": true
        },
        "amazon/nova-lite-v1": {
          "disabled": true
        },
        "openai/o1": {
          "disabled": true
        },
        "cohere/command-r7b-12-2024": {
          "disabled": true
        },
        "openai/gpt-4o-2024-11-20": {
          "disabled": true
        },
        "mistralai/mistral-large-2407": {
          "disabled": true
        },
        "qwen/qwen-2.5-coder-32b-instruct": {
          "disabled": true
        },
        "thedrummer/unslopnemo-12b": {
          "disabled": true
        },
        "anthracite-org/magnum-v4-72b": {
          "disabled": true
        },
        "qwen/qwen-2.5-7b-instruct": {
          "disabled": true
        },
        "meta-llama/llama-3.2-3b-instruct": {
          "disabled": true
        },
        "meta-llama/llama-3.2-1b-instruct": {
          "disabled": true
        },
        "qwen/qwen-2.5-72b-instruct": {
          "disabled": true
        },
        "cohere/command-r-plus-08-2024": {
          "disabled": true
        },
        "cohere/command-r-08-2024": {
          "disabled": true
        },
        "sao10k/l3.1-euryale-70b": {
          "disabled": true
        },
        "nousresearch/hermes-3-llama-3.1-70b": {
          "disabled": true
        },
        "nousresearch/hermes-3-llama-3.1-405b": {
          "disabled": true
        },
        "sao10k/l3-lunaris-8b": {
          "disabled": true
        },
        "openai/gpt-4o-2024-08-06": {
          "disabled": true
        },
        "meta-llama/llama-3.1-8b-instruct": {
          "disabled": true
        },
        "meta-llama/llama-3.1-70b-instruct": {
          "disabled": true
        },
        "openai/gpt-4o-mini-2024-07-18": {
          "disabled": true
        },
        "openai/gpt-4o-mini": {
          "disabled": true
        },
        "google/gemma-2-27b-it": {
          "disabled": true
        },
        "mistralai/mistral-nemo": {
          "disabled": true
        },
        "openai/gpt-4o-2024-05-13": {
          "disabled": true
        },
        "openai/gpt-4o": {
          "disabled": true
        },
        "mistralai/mixtral-8x22b-instruct": {
          "disabled": true
        },
        "microsoft/wizardlm-2-8x22b": {
          "disabled": true
        },
        "anthropic/claude-3-haiku": {
          "disabled": true
        },
        "mistralai/mistral-large": {
          "disabled": true
        },
        "qwen/qwen-plus": {
          "disabled": true
        },
        "openai/gpt-3.5-turbo-0613": {
          "disabled": true
        },
        "openai/gpt-4-turbo": {
          "disabled": true
        },
        "openai/gpt-4": {
          "disabled": true
        },
        "openai/gpt-3.5-turbo-instruct": {
          "disabled": true
        },
        "openai/gpt-3.5-turbo-16k": {
          "disabled": true
        },
        "mancer/weaver": {
          "disabled": true
        },
        "undi95/remm-slerp-l2-13b": {
          "disabled": true
        },
        "gryphe/mythomax-l2-13b": {
          "disabled": true
        },
        "openai/gpt-3.5-turbo": {
          "disabled": true
        }
      }
    },
    "deepseek": {
      "models": {
        "deepseek-flash": {
          "disabled": false
        },
        "deepseek-v4-flash": {
          "disabled": true
        },
        "deepseek-v4-flash-vision-exp": {
          "disabled": true
        },
        "deepseek-v4-pro": {
          "disabled": false
        }
      }
    }
  }
}
```

## Uninstall

```sh
rm -f ~/.claude/.i-have-adhd-always ~/.config/opencode/.i-have-adhd-always \
      ~/.config/opencode/.learn-always ~/.config/opencode/.visual-always
rm -rf ~/.config/opencode/vendor/i-have-adhd \
       ~/.config/opencode/vendor/learn ~/.config/opencode/vendor/visual
rm -rf ~/.agents/skills/{learn,visual,visual-explainer,openspec-*,typesafe-ai} \
       ~/.claude/skills/{learn,visual,visual-explainer,openspec-*,typesafe-ai}
```

Then the plugins through their own tools: `claude plugin uninstall`, `codex
plugin remove`, and the `plugin` entries in `opencode.json`.
