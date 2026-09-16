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

| Skill       | Default   | Comes from                       | Extra here                     |
| ----------- | --------- | -------------------------------- | ------------------------------ |
| ponytail    | always on | `DietrichGebert/ponytail` plugin | none — hooks itself            |
| i-have-adhd | always on | `ayghri/i-have-adhd` plugin      | flag files, and Codex AGENTS.md |
| learn       | on demand | `learnkit` repo                  | none                           |
| visual           | on demand | `visual-docs` repo                   | none                           |
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
| Codex       | plugin for `$i-have-adhd`, plus a region in `~/.codex/AGENTS.md` |

Codex is the one that needs help: upstream has no Codex hook, only a snippet to
paste. So `install.sh` clones upstream and writes the same `SKILL.md` body the
Claude hook injects into a `<!-- myskills:i-have-adhd:start -->` region. A
re-run refreshes it; the two flag-file tools need nothing.

OpenCode is also the one exception to throwaway clones — it loads a plugin from
a path, so that checkout persists at `~/.config/opencode/vendor/i-have-adhd` and
is `git pull`ed on re-runs.

**Codex needs one manual step for ponytail.** Codex will not run a plugin's
hooks until they are trusted. Open `codex`, run `/hooks`, trust ponytail's two.
Until then Codex has everything except ponytail's ladder.

Verified with a fresh session per tool — Codex answers `ponytail, i-have-adhd`;
Claude Code and OpenCode add `learn, visual`, whose descriptions they surface
without loading:

```sh
claude -p --model haiku 'name the skills in your context'
codex exec --skip-git-repo-check 'name the skills in your context'
opencode run 'name the skills in your context'
```

`openspec` is the one skill generated rather than installed: `openspec init` in
a throwaway project produces the skill and command trees, which are copied into
the tool homes — so every session sees `/opsx:*`. The specs and changes
themselves stay per project: `openspec init` in a repo writes only that repo's
`openspec/` directory.

## Switches

Independent, so turning one off leaves the others running.

| Skill       | Off              | On                            |
| ----------- | ---------------- | ----------------------------- |
| i-have-adhd | `stop adhd mode` | `adhd mode` or `/i-have-adhd` |
| ponytail    | `stop ponytail`  | `/ponytail lite\|full\|ultra` |
| visual      | `no diagrams`    | `/visual`                     |

Conversational — they last the session. To turn i-have-adhd off for good, delete
its flag file rather than saying it every session.

## Uninstall

```sh
rm -f ~/.claude/.i-have-adhd-always ~/.config/opencode/.i-have-adhd-always
sed -i '/<!-- myskills:.*:start -->/,/<!-- myskills:.*:end -->/d' ~/.codex/AGENTS.md
rm -rf ~/.config/opencode/vendor/i-have-adhd
```

Then the plugins through their own tools: `claude plugin uninstall`, `codex
plugin remove`, and the `plugin` entries in `opencode.json`.
