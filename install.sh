#!/bin/sh
# Aggregates the skills this machine should have, across Claude Code, Codex and
# OpenCode.
#
# Each skill is a standalone tool that installs itself its own way. There is no
# contract for them to satisfy and nothing shared to conform to — this file is
# the list, plus whatever wiring each one needs on top of its own installer. A
# new skill gets a new block, shaped however that skill happens to work.
#
# No agent-facing markdown lives here, and nothing is copied: where a skill has
# to be always on, the wiring points at the file the skill's own installer
# already wrote. Idempotent. Only tools on PATH get touched.
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

# mark <file> <name> <text> — replace this skill's region, append if absent.
# Per-skill markers, so one skill's wiring never disturbs another's.
mark() {
	f=$1
	mkdir -p "$(dirname "$f")"
	: >>"$f"
	sed "/^<!-- myskills:$2:start -->\$/,/^<!-- myskills:$2:end -->\$/d" "$f" >"$f.tmp"
	{
		cat "$f.tmp"
		echo "<!-- myskills:$2:start -->"
		printf '%s\n' "$3"
		echo "<!-- myskills:$2:end -->"
	} >"$f"
	rm -f "$f.tmp"
}

oc_json() { # <filter> [jq args...]
	f=$oc_home/opencode.json
	filter=$1
	shift
	mkdir -p "$oc_home"
	jq -e . "$f" >/dev/null 2>&1 || echo '{}' >"$f"
	jq "$@" "$filter" "$f" >"$f.tmp" && mv "$f.tmp" "$f"
}

# body <file> — a SKILL.md minus its YAML frontmatter. Frontmatter is for the
# command loader; in a global instruction file a bare `description:` line reads
# as an instruction.
body() { awk '/^---$/{c++; next} c>=2' "$1"; }

# --- ponytail -----------------------------------------------------------------
# Lazy senior dev mode. Ships its own plugin per tool, with intensity levels, a
# statusline and /ponytail-* commands, and injects its ruleset through a
# SessionStart hook — so there is nothing here to wire and nothing to copy.
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
mjs=$HOME/.claude/plugins/marketplaces/ponytail/.opencode/plugins/ponytail.mjs
if have opencode && have jq && [ -f "$mjs" ]; then
	oc_json '.plugin = ((.plugin // [] | map(select(. != $v))) + [$v])' --arg v "$mjs"
	echo "  opencode plugin"
fi

# --- i-have-adhd ---------------------------------------------------------------
# Output shaping. Upstream ships a plugin for each of these three and its own
# always-on mechanism, so none of this is hand-rolled — Claude and OpenCode watch
# for a flag file and inject the ruleset themselves. Codex has no such hook
# upstream, only a snippet to paste, so its AGENTS.md gets the same SKILL.md body
# the Claude hook injects, from a clone, in a region this script owns.
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
	codex plugin list 2>/dev/null | grep -q '^i-have-adhd@i-have-adhd' &&
		echo "  codex plugin — \$i-have-adhd" ||
		echo "  [FAIL] codex — codex plugin add i-have-adhd@i-have-adhd"
	if d=$(clone "$adhd"); then
		mark "$codex_home/AGENTS.md" i-have-adhd "$(body "$d/skills/i-have-adhd/SKILL.md")"
		echo "  codex — always on via ~/.codex/AGENTS.md"
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

# --- learn ----------------------------------------------------------------------
# Guided exploration, /learn. Installs itself to all three; on demand, no wiring
# beyond the always-on plugin its installer vendored — the path goes into
# opencode.json here, since this file owns that config. The mode itself is off
# until /learn or "learn always".
echo "learn"
if d=$(clone https://github.com/inifares23lab/learnkit.git); then
	run "$d/install.sh"
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
		for home in "$HOME/.claude/skills" "$HOME/.opencode/skills" "$codex_home/skills"; do
			rm -rf "$home/visual-explainer"
			mkdir -p "$home"
			cp -R "$src" "$home/visual-explainer"
		done
		mkdir -p "$oc_home/command"
		if cp -R "$src"/commands/*.md "$oc_home/command/" 2>/dev/null; then
			echo "  skill for opencode, claude, codex + opencode commands"
		else
			echo "  skill for opencode, claude, codex"
		fi
	else
		echo "  [FAIL] visual-explainer — no SKILL.md in the plugin tree"
	fi
fi

# --- typesafe-ai ------------------------------------------------------------------
# Build with TypeSafe/Jev: structured decisions (choice/score/noul) as API
# primitives. Claude gets the upstream plugin; opencode and codex get the skill
# directory straight from the upstream clone. No wiring and no always-on flag:
# it is a pure skill the agent reaches for when a task calls for it. One install
# path per tool — claude never also gets the copied directory, so its plugin and
# a stale copy can never disagree.
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
		for home in "$HOME/.opencode/skills" "$codex_home/skills"; do
			rm -rf "$home/typesafe-ai"
			mkdir -p "$home"
			cp -R "$src" "$home/typesafe-ai"
		done
		echo "  skill for opencode, codex"
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
	# Generated in a throwaway project: only the .opencode/.claude/.agents trees
	# belong on the machine, and the scratch openspec/ dies with it. Stale
	# openspec-* files go first, so a workflow removed upstream does not linger.
	opsx=$(mktemp -d)
	git init -q "$opsx" 2>/dev/null || true
	if (cd "$opsx" && openspec init --tools opencode,claude,codex \
			--no-copilot-cloud --no-animation >/dev/null 2>&1); then
		for d in "$HOME/.opencode/skills" "$HOME/.claude/skills" "$HOME/.agents/skills"; do
			mkdir -p "$d"
			rm -rf "$d"/openspec-*
		done
		cp -R "$opsx/.opencode/skills/." "$HOME/.opencode/skills/"
		cp -R "$opsx/.claude/skills/." "$HOME/.claude/skills/"
		cp -R "$opsx/.agents/skills/." "$HOME/.agents/skills/"
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
