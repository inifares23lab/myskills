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
# skill ships as a plugin, the plugin is the only copy. Idempotent, unless
# --force: a normal run fixes what is broken or missing and leaves the rest
# unchanged; --force clears only the plugins and skills this installer manages,
# then reinstalls them — nothing else is touched, and the repo is only ever
# read. Only tools on PATH get touched.
set -eu

force=0
for arg in "$@"; do
	case $arg in
	--force) force=1 ;;
	*)
		echo "usage: install.sh [--force]" >&2
		exit 2
		;;
	esac
done

codex_home=${CODEX_HOME:-$HOME/.codex}
oc_home=${XDG_CONFIG_HOME:-$HOME/.config}/opencode
oc_plugins=$oc_home/plugins
repo=$(cd "$(dirname "$0")" && pwd)

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
	# OpenCode reads JSONC and tolerates trailing commas; jq does not. The
	# config has carried such a comma before — without the fallback below,
	# the parse failure would reset the whole file to {}. Sanitize, verify,
	# and keep the sanitized form only when it parses.
	if ! jq -e . "$f" >/dev/null 2>&1; then
		perl -0777 -pe 's/,(\s*[}\]])/$1/g' "$f" >"$f.tmp" 2>/dev/null
		if [ -s "$f.tmp" ] && jq -e . "$f.tmp" >/dev/null 2>&1; then
			mv "$f.tmp" "$f"
			echo "  repaired $f (trailing commas stripped for jq)"
		else
			rm -f "$f.tmp"
		fi
	fi
	jq -e . "$f" >/dev/null 2>&1 || echo '{}' >"$f"
	jq "$@" "$filter" "$f" >"$f.tmp" && mv "$f.tmp" "$f"
}

# vend <name> [subpath...] — build a deployable opencode plugin tree at
# $oc_plugins/<name> from the pristine source in vendor/<name> plus the patch
# series in patches/<name>, and add the root index.mjs shim the v2 directory
# loader needs. Whole tree when no subpaths are given. The vendored source
# stays in the repo (read-only) — the built tree is copied into the config
# home, so opencode.json never references this repo and the repo can be thrown
# away after install. Failure-safe: the previously built tree stays in place
# until the staged build is complete, so a patch that no longer applies never
# half-updates. No network.
vend() {
	name=$1
	shift
	src=$repo/vendor/$name
	dest=$oc_plugins/$name
	if [ ! -d "$src" ]; then
		echo "  [FAIL] $name — vendored source missing ($src); run ./refresh.sh"
		return 1
	fi
	stage=$tmp/vend-$name
	rm -rf "$stage"
	mkdir -p "$stage"
	if [ "$#" -gt 0 ]; then
		for p in "$@"; do
			if [ ! -e "$src/$p" ]; then
				echo "  [FAIL] $name — no $p in the vendored source"
				return 1
			fi
			cp -R "$src/$p" "$stage/$p"
		done
	else
		cp -R "$src/." "$stage/"
	fi
	for p in "$repo/patches/$name"/*.patch; do
		[ -e "$p" ] || continue
		if ! (cd "$stage" && git apply -p1 "$p") 2>/dev/null &&
			! (cd "$stage" && patch --silent -p1 <"$p") 2>/dev/null; then
			echo "  [FAIL] $name — $(basename "$p") no longer applies to vendor/$name; rebase patches/$name"
			return 1
		fi
	done
	cat >"$stage/index.mjs" <<EOF
// Vendored $name OpenCode plugin — root shim.
//
// OpenCode 2 loads a local plugin directory via its index.mjs; the real
// plugin lives at ./.opencode/plugins/$name.mjs (upstream layout, kept intact
// so its relative requires work). Installed by install.sh from vendor/$name
// plus patches/$name into $oc_plugins — the shim is generated, the rest is
// patched upstream source.
export { default } from './.opencode/plugins/$name.mjs';
EOF
	mkdir -p "$(dirname "$dest")"
	rm -rf "$dest"
	mv "$stage" "$dest"
	oc_json '.plugins = (((.plugins // []) + [$v]) | unique)' --arg v "$dest"
	echo "  opencode plugin — installed $dest (vendor/$name + patches/$name)"
}

# emit_skill <name> <bodyfile> <description> — write a SKILL.md from a vendored
# body file, the way the upstream installers do. Idempotent.
emit_skill() {
	name=$1 body=$2 desc=$3
	for dest in "$HOME/.agents/skills/$name/SKILL.md" "$HOME/.claude/skills/$name/SKILL.md"; do
		if [ -L "$dest" ]; then rm "$dest"; fi
		if [ -L "$(dirname "$dest")" ]; then rm "$(dirname "$dest")"; fi
		mkdir -p "$(dirname "$dest")"
		{ echo '---'; printf '%s\n' "name: $name"; printf '%s\n' 'description: >'; printf '  %s\n' "$desc"; echo '---'; echo; cat "$body"; } >"$dest"
	done
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
# Claude and Codex install it from its marketplace; OpenCode takes the vendored
# built from vendor/ponytail plus patches/ponytail (upstream still ships the v1
# plugin API, which OpenCode 2 rejects — see vendor/patches/ponytail).
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
	# One-time migration of the v1 plugin config to the v2 plugins array:
	# drop the npm ponytail entry, the bare .mjs vendor paths (v2 rejects
	# both), the retired $oc_home/vendor deployment location, and the retired
	# $repo/build deployment location (plugins used to register straight into
	# this repo's build/; opencode.json must never reference the repo). Keep
	# any other entries. Content-stable under re-runs. The vend calls below
	# then register the installed plugin directories under $oc_home/plugins.
	oc_json '
		(if (.plugin | type) == "array"
		then [.plugin[] | select(type == "string") | select(endswith(".mjs") | not) | select(. != "@dietrichgebert/ponytail")]
		else [] end) as $kept
		| .plugins = ((($kept + (.plugins // []))
			| map(select(test("/opencode/vendor/") | not))
			| map(select(test("/build/(ponytail|i-have-adhd|learn|visual)$") | not)))
			| unique)
		| del(.plugin)
	'
	if [ "$force" = 1 ]; then
		# Forced reinstall, scoped to what this installer manages: the four
		# installed plugin trees and the skills it deploys. Anything else —
		# including plugins and skills installed by other means — is left
		# alone, and the repo's vendor/ and patches/ are only ever read.
		for n in ponytail i-have-adhd learn visual; do
			rm -rf "$oc_plugins/$n"
		done
		rm -rf "$oc_home/skills"/ponytail* "$oc_home/skills/i-have-adhd"
		echo "  forced: cleared the installed plugins and managed skills"
	fi
	vend ponytail
	# Ponytail's bundled skills have no plugin skills-path mechanism in v2;
	# the opencode-only skills dir takes over. cp -R is content-stable.
	if [ -d "$repo/vendor/ponytail/skills" ]; then
		mkdir -p "$oc_home/skills"
		for s in "$repo"/vendor/ponytail/skills/*/; do
			n=$(basename "$s")
			rm -rf "$oc_home/skills/$n"
			cp -R "$s" "$oc_home/skills/$n"
		done
		echo "  skills into $oc_home/skills (ponytail, ponytail-*)"
	fi
fi
# Old per-tool copies from earlier layouts. Ponytail's skills now install to
# the opencode-only skills dir (see above); the tool-home copies stay removed.
rm -rf "$codex_home/skills/ponytail" "$HOME/.opencode/skills/ponytail" \
	"$HOME/.claude/skills/ponytail"

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
	# Vendored source + the v2 patch replace the install-time git clone. The
	# skill goes to the opencode-only skills dir: v2 has no config
	# skills.paths hook, and ~/.agents/skills would surface it to codex too.
	vend i-have-adhd .opencode skills
	rm -rf "$oc_home/skills/i-have-adhd"
	cp -R "$repo/vendor/i-have-adhd/skills/i-have-adhd" "$oc_home/skills/i-have-adhd"
	touch "$oc_home/.i-have-adhd-always"
	echo "  opencode plugin — always on via $oc_home/.i-have-adhd-always"
fi
# Old per-tool copies from earlier layouts. OpenCode loads skills bundled with
# plugins — npm or path — so it needs no raw copies at all.
rm -rf "$codex_home/skills/i-have-adhd" "$HOME/.opencode/skills/i-have-adhd" \
	"$HOME/.claude/skills/i-have-adhd" "$oc_home/skills/i-have-adhd"

# --- learn ----------------------------------------------------------------------
# Guided exploration, /learn. Vendored: the skill body (LEARN.md) and its
# description come from the pristine snapshot under vendor/learn, and the
# always-on plugin is built from vendor/learn plus patches/learn — no clone at
# install time.
learn_desc='Interactive, user-steered exploration of any subject to any depth — code, mathematics, biology, film, a market, a machine, or an idea. Explains mechanism, challenges the framing, and brainstorms one move at a time, moving down into how something happens, up into why its class of thing exists, across to alternatives and prior art, apart into components and steps, back to the forces that shaped it, or sideways onto a chosen lens such as energy, cost, latency, rigour, or audience. Checks what stayed with recall and teach-it-back drills, and tunes depth to how well predictions land. Resumes open threads from LEARNING.md and appends the trail back to it. A session mode — "stop learn mode" turns it off for the rest of the session, and "learn always" keeps it on in every session until "learn never" removes it. Use when asked to learn about, explore, dissect, study, unpack, or go deeper on anything.'
echo "learn"
if [ -f "$repo/vendor/learn/LEARN.md" ]; then
	emit_skill learn "$repo/vendor/learn/LEARN.md" "$learn_desc"
	echo "  skill for claude + ~/.agents (codex, opencode)"
	if have opencode; then
		mkdir -p "$oc_home/command"
		{ echo '---'; printf '%s\n' "description: $learn_desc"; echo '---'; echo; cat "$repo/vendor/learn/LEARN.md"; } >"$oc_home/command/learn.md"
	fi
	vend learn .opencode
	echo "  opencode always-on plugin"
else
	echo "  [FAIL] learn — vendored snapshot missing; run ./refresh.sh"
fi

# --- visual ---------------------------------------------------------------------
# Figures in text documents, /visual. Same shape as learn: vendored snapshot,
# no clone at install time.
visual_desc='Add ASCII diagrams, figures, and hand-written SVG visual aids to otherwise text-only documents, on any subject — engineering, science, business, law, music, anything whose parts relate. Matches the shape of the relationship rather than the domain, so a protein, a supply chain, and a service mesh that share a shape get the same figure. Picks the form (box-and-line, sequence ladder, state machine, pipeline, layer stack, tree, timeline, field map, bar row, scale drawing, plot, arrow field) and the medium (inline ASCII for topology, SVG when positions carry meaning — angles, curves, scale, continuous values), lays a column ruler before drawing, and ships the figure aligned, labelled, and under 72 columns. Draws by default rather than describing, puts the figure above the detail it maps, and deletes the prose it replaces. A session mode — "no diagrams" turns it off for the rest of the session, and "visual always" keeps it on in every session until "visual never" removes it. Use when writing or revising a spec, proposal, design note, plan, README, learning notes, or any page working out how something fits together.'
echo "visual"
if [ -f "$repo/vendor/visual/VISUAL.md" ]; then
	emit_skill visual "$repo/vendor/visual/VISUAL.md" "$visual_desc"
	echo "  skill for claude + ~/.agents (codex, opencode)"
	if have opencode; then
		mkdir -p "$oc_home/command"
		{ echo '---'; printf '%s\n' "description: $visual_desc"; echo '---'; echo; cat "$repo/vendor/visual/VISUAL.md"; } >"$oc_home/command/visual.md"
	fi
	vend visual .opencode
	echo "  opencode always-on plugin"
else
	echo "  [FAIL] visual — vendored snapshot missing; run ./refresh.sh"
fi

# --- visual-explainer -------------------------------------------------------------
# Self-contained HTML visual explanations — diagrams, decks, diff and plan
# reviews, project recaps. A whole plugin tree per tool home, the way its own
# installer ships it; its command templates join the opencode command dir.
# Served from the vendored snapshot — no clone at install time.
echo "visual-explainer"
src=$repo/vendor/visual-explainer/plugins/visual-explainer
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
	echo "  [FAIL] visual-explainer — vendored snapshot missing; run ./refresh.sh"
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
if [ -f "$repo/vendor/typesafe-ai/skills/typesafe-ai/SKILL.md" ]; then
	rm -rf "$HOME/.agents/skills/typesafe-ai" \
		"$HOME/.opencode/skills/typesafe-ai" "$codex_home/skills/typesafe-ai"
	mkdir -p "$HOME/.agents/skills"
	cp -R "$repo/vendor/typesafe-ai/skills/typesafe-ai" "$HOME/.agents/skills/typesafe-ai"
	echo "  skill in ~/.agents/skills (codex, opencode)"
else
	echo "  [FAIL] typesafe-ai — vendored snapshot missing; run ./refresh.sh"
fi

# --- openspec ---------------------------------------------------------------------
# Spec-driven change, /opsx:*. Two halves. The CLI on PATH does the work (a
# missing CLI installs from the vendored npm tree in vendor/openspec — no
# registry); the skill files are generated at install time by that
# local CLI in a throwaway project, so every session sees /opsx:* — while
# specs and changes stay per project, in each repo's own openspec/.
echo "openspec"
# install_cli — npm install -g from the vendored tree, with the reason on
# failure (permission walls on a root-owned global prefix are common).
install_cli() {
	err=$(npm install -g "$repo/vendor/openspec" 2>&1) && rc=0 || rc=$?
	if [ "$rc" -eq 0 ]; then
		echo "  installed from vendor — $(openspec --version 2>/dev/null || echo yes)"
	else
		echo "  [FAIL] npm install -g from $repo/vendor/openspec"
		printf '%s\n' "$err" | grep -m1 "npm error" | sed 's/^/    /'
		printf '    (fix the npm global prefix permissions, then re-run)\n'
	fi
}
if have openspec; then
	echo "  present — $(openspec --version 2>/dev/null || echo yes)"
	if [ -d "$repo/vendor/openspec" ]; then
		vendored=$(jq -r .version "$repo/vendor/openspec/package.json" 2>/dev/null)
		if [ "$force" = 1 ]; then
			# Forced reinstall: the CLI is only installed when missing on a
			# normal run, so --force is how a bumped MANIFEST ref lands.
			install_cli
		elif [ -n "$vendored" ] && [ "$(openspec --version 2>/dev/null)" != "$vendored" ]; then
			echo "  note: vendor has $vendored, installed differs — run install.sh --force to update"
		fi
	fi
elif [ -d "$repo/vendor/openspec" ]; then
	install_cli
else
	echo "  [skip] no openspec, no vendored CLI"
fi
if have openspec && have git; then
	# Generated in a throwaway project by the local CLI: only the .claude/.agents
	# trees belong on the machine — .agents is the shared home codex and opencode
	# both read, .claude the copy claude needs. The scratch openspec/ dies with
	# it. Stale openspec-* files go first, so a workflow removed upstream does
	# not linger.
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
		echo "  skills for opencode, claude, codex"
	else
		echo "  [FAIL] openspec init — global skills not generated"
	fi
	rm -rf "$opsx"
fi
echo "  per project: openspec init"
