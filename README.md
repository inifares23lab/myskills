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
