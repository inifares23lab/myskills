#!/bin/sh
# Aggregates the skills this machine should have, across Claude Code, Codex and
# OpenCode.
#
# Each skill is a standalone tool that installs itself its own way. There is no
# contract for them to satisfy and nothing shared to conform to — this file is
# the list, plus whatever wiring each one needs on top of its own installer. A
# new skill gets a new block, shaped however that skill happens to work.
#
# No agent-facing markdown lives here. Plain skill copies go to ~/.agents/skills,
# which codex and opencode both read; claude is the exception and gets
# ~/.claude/skills copies, since it does not read ~/.agents/skills. Where a
# skill ships as a plugin, the plugin is the only copy. Idempotent. Only tools
# on PATH get touched.
set -eu

codex_home=${CODEX_HOME:-$HOME/.codex}
oc_home=${XDG_CONFIG_HOME:-$HOME/.config}/opencode

have() { command -v "$1" >/dev/null 2>&1; }
run() { if [ -x "$1" ]; then "$1"; else sh "$1"; fi; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

# clone <url> — print the checkout, or fail by name. Shallow, and thrown away on
# exit: no cache, and no checkout of anything has to stay put, including this one.
clone() {
	n=$(basename "$1" .git)
	if git clone --quiet --depth 1 "$1" "$tmp/$n" 2>/dev/null; then
		printf '%s' "$tmp/$n"
	else
		echo "  [FAIL] cannot clone $1" >&2
		return 1
	fi
}

oc_json() { # <filter> [jq args...]
	f=$oc_home/opencode.json
	filter=$1
	shift
	mkdir -p "$oc_home"
	jq -e . "$f" >/dev/null 2>&1 || echo '{}' >"$f"
	jq "$@" "$filter" "$f" >"$f.tmp" && mv "$f.tmp" "$f"
}

# share <name> — leave one plain copy of a skill, in ~/.agents/skills, which
# both codex and opencode read. Source: whichever per-tool copy an installer
# just wrote. The per-tool copies in $codex_home/skills and ~/.opencode/skills
# are then removed — neither tool reads them anymore. ~/.claude/skills keeps
# its copy: claude is the one tool that does not read ~/.agents/skills.
share() {
	for s in "$HOME/.claude/skills/$1" "$codex_home/skills/$1" "$HOME/.opencode/skills/$1"; do
		if [ -d "$s" ]; then
			rm -rf "$HOME/.agents/skills/$1"
			mkdir -p "$HOME/.agents/skills"
			cp -R "$s" "$HOME/.agents/skills/$1"
			break
		fi
	done
	rm -rf "$codex_home/skills/$1" "$HOME/.opencode/skills/$1"
	if [ -d "$HOME/.agents/skills/$1" ]; then
		echo "  shared: ~/.agents/skills/$1 (codex, opencode)"
	fi
}

# --- ponytail -----------------------------------------------------------------
# Lazy senior dev mode. Ships its own plugin per tool, with intensity levels, a
# statusline and /ponytail-* commands, and injects its ruleset through a
# SessionStart hook — so there is nothing here to wire and nothing to copy.
# Claude and Codex install it from its marketplace; OpenCode takes the npm
# package, which bundles the opencode plugin and the skills.
echo "ponytail"
if have claude; then
	claude plugin marketplace add DietrichGebert/ponytail >/dev/null 2>&1 || true
	claude plugin install ponytail@ponytail >/dev/null 2>&1 || true
	claude plugin list 2>/dev/null | grep -q ponytail &&
		echo "  claude plugin" ||
		echo "  [FAIL] claude — claude plugin install ponytail@ponytail"
fi
if have codex; then
	codex plugin marketplace add DietrichGebert/ponytail >/dev/null 2>&1 || true
	codex plugin add ponytail@ponytail >/dev/null 2>&1 || true
	codex plugin list 2>/dev/null | grep -q '^ponytail@ponytail' &&
		echo "  codex plugin — trust its two hooks once in /hooks" ||
		echo "  [FAIL] codex — a 'ponytail' marketplace from another source blocks it; codex plugin marketplace remove ponytail, then re-run"
fi
if have opencode && have jq; then
	# One config line, no checkouts and no raw skill copies: opencode installs
	# npm plugins itself and loads the skills bundled in the package.
	oc_json '.plugin = (((.plugin // []) | map(select((test("ponytail[.]mjs$") or test("@dietrichgebert/ponytail")) | not))) + ["@dietrichgebert/ponytail"])'
	echo "  opencode plugin (@dietrichgebert/ponytail from npm)"
fi
# Old per-tool copies from earlier layouts: every tool now gets ponytail
# through a plugin.
rm -rf "$codex_home/skills/ponytail" "$HOME/.opencode/skills/ponytail" \
	"$HOME/.claude/skills/ponytail" "$oc_home/skills/ponytail"

# --- i-have-adhd ---------------------------------------------------------------
# Output shaping. Upstream ships a plugin for each of these three and its own
# always-on mechanism, so none of this is hand-rolled — Claude and OpenCode
# watch for a flag file and inject the ruleset themselves. Codex's plugin
# bundles the same SessionStart hook, gated on the same
# ~/.claude/.i-have-adhd-always flag Claude uses — it just has to be trusted
# once in /hooks. An earlier layout pasted the body into ~/.codex/AGENTS.md;
# that region is removed here.
adhd=https://github.com/ayghri/i-have-adhd.git
echo "i-have-adhd"
if have claude; then
	claude plugin marketplace add ayghri/i-have-adhd >/dev/null 2>&1 || true
	claude plugin install i-have-adhd@i-have-adhd >/dev/null 2>&1 || true
	if claude plugin list 2>/dev/null | grep -q i-have-adhd; then
		touch "$HOME/.claude/.i-have-adhd-always"
		echo "  claude plugin — always on via ~/.claude/.i-have-adhd-always"
	else
		echo "  [FAIL] claude — claude plugin install i-have-adhd@i-have-adhd"
	fi
fi
if have codex; then
	codex plugin marketplace add ayghri/i-have-adhd --ref main >/dev/null 2>&1 || true
	codex plugin add i-have-adhd@i-have-adhd >/dev/null 2>&1 || true
	if codex plugin list 2>/dev/null | grep -q '^i-have-adhd@i-have-adhd'; then
		touch "$HOME/.claude/.i-have-adhd-always"
		echo "  codex plugin — trust its SessionStart hook once in /hooks; always on via ~/.claude/.i-have-adhd-always"
	else
		echo "  [FAIL] codex — codex plugin add i-have-adhd@i-have-adhd"
	fi
	# Migration from the AGENTS.md-region layout this script once owned.
	ag=$codex_home/AGENTS.md
	if [ -f "$ag" ] && grep -q 'myskills:i-have-adhd' "$ag"; then
		sed '/^<!-- myskills:i-have-adhd:start -->$/,/^<!-- myskills:i-have-adhd:end -->$/d' "$ag" >"$ag.tmp" &&
			mv "$ag.tmp" "$ag"
	fi
fi
if have opencode && have jq; then
	# OpenCode loads a plugin from a path, so this is the one checkout that has
	# to persist. Upstream's own suggested location.
	vend=$oc_home/vendor/i-have-adhd
	if [ -d "$vend/.git" ]; then
		git -C "$vend" pull --quiet --ff-only >/dev/null 2>&1 || true
	else
		mkdir -p "$(dirname "$vend")"
		git clone --quiet "$adhd" "$vend" >/dev/null 2>&1 || true
	fi
	if [ -f "$vend/.opencode/plugins/i-have-adhd.mjs" ]; then
		oc_json '.plugin = ((.plugin // [] | map(select(. != $v))) + [$v])' \
			--arg v "$vend/.opencode/plugins/i-have-adhd.mjs"
		touch "$oc_home/.i-have-adhd-always"
		echo "  opencode plugin — always on via $oc_home/.i-have-adhd-always"
	else
		echo "  [FAIL] opencode — cannot vendor $adhd to $vend"
	fi
fi
# Old per-tool copies from earlier layouts. OpenCode loads skills bundled with
# plugins — npm or path — so it needs no raw copies at all.
rm -rf "$codex_home/skills/i-have-adhd" "$HOME/.opencode/skills/i-have-adhd" \
	"$HOME/.claude/skills/i-have-adhd" "$oc_home/skills/i-have-adhd"

# --- learn ----------------------------------------------------------------------
# Guided exploration, /learn. Installs itself to all three; on demand, no wiring
# beyond the always-on plugin its installer vendored — the path goes into
# opencode.json here, since this file owns that config. The mode itself is off
# until /learn or "learn always".
echo "learn"
if d=$(clone https://github.com/inifares23lab/learnkit.git); then
	run "$d/install.sh"
	share learn
	mjs=$oc_home/vendor/learn/learn.mjs
	if have jq && [ -f "$mjs" ]; then
		oc_json '.plugin = ((.plugin // [] | map(select(. != $v))) + [$v])' --arg v "$mjs"
		echo "  opencode always-on plugin"
	fi
fi

# --- visual ---------------------------------------------------------------------
# Figures in text documents, /visual. Same shape as learn.
echo "visual"
if d=$(clone https://github.com/inifares23lab/visual-docs.git); then
	run "$d/install.sh"
	share visual
	mjs=$oc_home/vendor/visual/visual.mjs
	if have jq && [ -f "$mjs" ]; then
		oc_json '.plugin = ((.plugin // [] | map(select(. != $v))) + [$v])' --arg v "$mjs"
		echo "  opencode always-on plugin"
	fi
fi

# --- visual-explainer -------------------------------------------------------------
# Self-contained HTML visual explanations — diagrams, decks, diff and plan
# reviews, project recaps. A whole plugin tree per tool home, the way its own
# installer ships it; its command templates join the opencode command dir.
echo "visual-explainer"
if d=$(clone https://github.com/nicobailon/visual-explainer.git); then
	src="$d/plugins/visual-explainer"
	if [ -f "$src/SKILL.md" ]; then
		for home in "$HOME/.agents/skills" "$HOME/.claude/skills"; do
			rm -rf "$home/visual-explainer"
			mkdir -p "$home"
			cp -R "$src" "$home/visual-explainer"
		done
		mkdir -p "$oc_home/command"
		if cp -R "$src"/commands/*.md "$oc_home/command/" 2>/dev/null; then
			echo "  skill for claude + ~/.agents (codex, opencode) + opencode commands"
		else
			echo "  skill for claude + ~/.agents (codex, opencode)"
		fi
	else
		echo "  [FAIL] visual-explainer — no SKILL.md in the plugin tree"
	fi
fi

# --- typesafe-ai ------------------------------------------------------------------
# Build with TypeSafe/Jev: structured decisions (choice/score/noul) as API
# primitives. Claude gets the upstream plugin; the one plain copy goes to
# ~/.agents/skills, which codex and opencode both read. No wiring and no
# always-on flag: it is a pure skill the agent reaches for when a task calls
# for it. One install path per tool — claude never also gets the copied
# directory, so its plugin and a stale copy can never disagree.
echo "typesafe-ai"
if have claude; then
	claude plugin marketplace add typesafe-ai/skills >/dev/null 2>&1 || true
	claude plugin install typesafe@typesafe-ai >/dev/null 2>&1 || true
	claude plugin list 2>/dev/null | grep -q typesafe &&
		echo "  claude plugin" ||
		echo "  [FAIL] claude — claude plugin install typesafe@typesafe-ai"
fi
if d=$(clone https://github.com/typesafe-ai/skills.git); then
	src="$d/skills/typesafe-ai"
	if [ -f "$src/SKILL.md" ]; then
		rm -rf "$HOME/.agents/skills/typesafe-ai" \
			"$HOME/.opencode/skills/typesafe-ai" "$codex_home/skills/typesafe-ai"
		mkdir -p "$HOME/.agents/skills"
		cp -R "$src" "$HOME/.agents/skills/typesafe-ai"
		echo "  skill in ~/.agents/skills (codex, opencode)"
	else
		echo "  [FAIL] typesafe-ai — no SKILL.md in the clone"
	fi
fi

# --- openspec ---------------------------------------------------------------------
# Spec-driven change, /opsx:*. Two halves. The CLI on PATH does the work; the
# skill and command files are generated once into the tool homes, so every
# session sees /opsx:* — while specs and changes stay per project, in each
# repo's own openspec/.
echo "openspec"
if have openspec; then
	echo "  present — $(openspec --version 2>/dev/null || echo yes)"
elif have npm; then
	npm install -g @fission-ai/openspec@latest >/dev/null 2>&1 &&
		echo "  installed" || echo "  [FAIL] npm install -g @fission-ai/openspec@latest"
else
	echo "  [skip] no npm"
fi
if have openspec && have git; then
	# Generated in a throwaway project: only the .claude/.agents trees belong on
	# the machine — .agents is the shared home codex and opencode both read,
	# .claude the copy claude needs. The scratch openspec/ dies with it. Stale
	# openspec-* files go first, so a workflow removed upstream does not linger.
	opsx=$(mktemp -d)
	git init -q "$opsx" 2>/dev/null || true
	if (cd "$opsx" && openspec init --tools opencode,claude,codex \
			--no-copilot-cloud --no-animation >/dev/null 2>&1); then
		for d in "$HOME/.agents/skills" "$HOME/.claude/skills"; do
			mkdir -p "$d"
			rm -rf "$d"/openspec-*
		done
		cp -R "$opsx/.agents/skills/." "$HOME/.agents/skills/"
		cp -R "$opsx/.claude/skills/." "$HOME/.claude/skills/"
		mkdir -p "$oc_home/command"
		rm -f "$oc_home/command"/opsx-*.md
		cp -R "$opsx/.opencode/commands/." "$oc_home/command/"
		mkdir -p "$HOME/.claude/commands"
		rm -rf "$HOME/.claude/commands/opsx"
		cp -R "$opsx/.claude/commands/." "$HOME/.claude/commands/"
		echo "  skills + commands for opencode, claude, codex"
	else
		echo "  [FAIL] openspec init — global skills not generated"
	fi
	rm -rf "$opsx"
fi
echo "  per project: openspec init"
