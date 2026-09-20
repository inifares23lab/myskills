# Vendoring

Everything the installer deploys is vendored in this repo. Nothing is fetched
from upstream at install time — install.sh only reads local files.

## Layout

    MANIFEST             one line per upstream source: <name> <type> <url> <ref>
                         npm ref: exact version, dist-tag (latest), or range —
                         resolved to one version and recorded. git ref: branch,
                         tag (annotated tags peel to the commit), or latest =
                         newest tag by version sort, else HEAD.
    refresh.sh           re-fetches vendor/ from MANIFEST. Refreshes only —
                         never applies patches, never touches patches/, never
                         touches the live system.
    vendor/<project>/    pristine upstream source, unchanged. The only added
                         file is vendor/.refs/<project>, recording the exact
                         version/commit each snapshot was taken from.
    patches/<project>/   local modifications as patch series against the
                         pristine sources (applied with git apply -p1; verified
                         to apply clean). Only ponytail and i-have-adhd carry
                         patches — learn and visual are ours and the v2 port
                         is merged upstream, so vendor/ already holds v2 code
                         and no patch is needed.
    build/<project>/     gitignored — what install.sh deploys: the pristine
                         source subset plus the patch series plus a generated
                         index.mjs shim. opencode.json registers these repo
                         paths directly; nothing is copied into ~/.config.

## Projects

| project         | source                         | deploys                                  |
|-----------------|--------------------------------|------------------------------------------|
| ponytail        | npm @dietrichgebert/ponytail   | opencode plugin + skills                 |
| i-have-adhd     | git ayghri/i-have-adhd         | opencode plugin + skill                  |
| learn           | git inifares23lab/learnkit     | opencode plugin + skill + command        |
| visual          | git inifares23lab/visual-docs  | opencode plugin + skill + command        |
| visual-explainer| git nicobailon/visual-explainer| skill tree + opencode commands           |
| typesafe-ai     | git typesafe-ai/skills         | skill tree                               |
| openspec        | npm @fission-ai/openspec       | CLI (npm i -g from the vendored tree)    |

## The v2 plugin ports

OpenCode 2 rejected all four v1 plugins. The ports map the v1 API onto the v2
API, verified against OpenCode 2.0.11:

- default export: `{ id, setup(ctx) }` instead of a function returning hooks
- `experimental.chat.system.transform` → `ctx.session.hook("context")`, pushing
  a `{ type: "text", text }` block
- ponytail/i-have-adhd `config` hooks → `ctx.command.transform` for commands;
  bundled skills move to native discovery (install.sh copies them into
  `~/.config/opencode/skills/`)
- ponytail's `command.execute.before` (no v2 equivalent) → `/ponytail` becomes
  an execute-command that persists the mode itself, then submits the template

learn and visual are ours: the v2 port is merged upstream, so their vendor
snapshots are already v2. Only ponytail and i-have-adhd need patch series,
since we don't control those upstreams.

OpenCode 2 loads a local plugin directory via a root `index.mjs` (package.json
main/exports is ignored for directory entries, silently). install.sh generates
that shim; the rest of each deployed tree is upstream source plus the patch
series, applied at install time into a staging dir and swapped in atomically.

## Refreshing (deliberate, manual)

    ./refresh.sh          # updates vendor/ only, reports the resolved refs

Then diff vendor/ against patches/, rework the patch series if needed, and
only then run install.sh, which applies them. learn and visual are ours
(inifares23lab) — patch commits lift cleanly into upstream PRs.

openspec note: the generated skills/commands are produced at install time by
the CLI itself, so the MANIFEST ref also pins the CLI version those workflows
come from. Bump the ref and re-run install.sh to move versions together.
