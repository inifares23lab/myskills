#!/bin/sh
# Refreshes the pristine upstream snapshots under vendor/, from the sources and
# refs declared in MANIFEST (both at the repo root).
#
# This script ONLY refreshes. It does not apply patches, does not touch
# anything outside vendor/ (patches/ is never read or written), does not run
# install.sh, and does not touch the live system. Each project dir under
# vendor/ stays exactly its upstream source; the only thing added beside them
# is vendor/.refs/<name>, recording the exact version/commit each snapshot was
# taken from, so a later refresh can show what moved.
#
# After a refresh, diff vendor/ against patches/ yourself; applying upstream
# changes to the patch series is a deliberate, manual step.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
vendor=$here/vendor
manifest=$here/MANIFEST

have() { command -v "$1" >/dev/null 2>&1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

# A private npm cache: refresh must not fail on unreadable entries in the
# user's shared cache (EACCES on ~/.npm/_cacache), nor pollute it.
export npm_config_cache="$tmp/npm-cache"

# fetched <name> <resolved-ref> — record what a snapshot was taken from.
fetched() {
	printf '%s\n' "$2" >"$vendor/.refs/$1"
}

fetch_npm() { # <name> <pkg> <ref: version | dist-tag | range>
	name=$1 pkg=$2 ref=$3
	if ! have npm; then
		echo "  [SKIP] $name — npm not on PATH" >&2
		return 1
	fi
	# Resolve whatever ref form was given down to one exact version, so the
	# recorded ref is reproducible. A range can match many versions — npm
	# prints one line per match, the version always the last field.
	ver=$(npm view "$pkg@$ref" version 2>/dev/null | awk 'NF {print $NF}' |
		tail -1 | tr -d "'\"")
	if [ -z "$ver" ]; then
		echo "  [FAIL] $name — cannot resolve $pkg@$ref" >&2
		return 1
	fi
	mkdir -p "$vendor/$name"
	# Pack into a per-fetch dir: a shared tmp once handed an earlier fetch's
	# tarball to a later npm fetch (alphabetical glob), and unpacked the wrong
	# package entirely.
	packdir="$tmp/pack-$name"
	rm -rf "$packdir"
	mkdir -p "$packdir"
	(cd "$packdir" && npm pack "$pkg@$ver" --silent >/dev/null 2>&1)
	tarball=$(ls "$packdir"/*.tgz 2>/dev/null | head -1) || {
		echo "  [FAIL] $name — npm pack $pkg@$ver produced no tarball" >&2
		return 1
	}
	stage="$tmp/$name"
	mkdir -p "$stage"
	tar xzf "$tarball" -C "$stage"
	# Trust but verify: the tarball must be the package we asked for.
	got=$(jq -r .name "$stage/package/package.json" 2>/dev/null)
	if [ "$got" != "$pkg" ]; then
		echo "  [FAIL] $name — npm pack delivered '$got' instead of '$pkg'" >&2
		return 1
	fi
	mv "$stage/package" "$stage/tree"
	# Vendor the production dependency tree too: a global install from a
	# directory is symlinked, so the CLI resolves deps from this tree — and
	# npm tarballs never ship node_modules.
	if jq -e '.dependencies' "$stage/tree/package.json" >/dev/null 2>&1; then
		if ! (cd "$stage/tree" && npm install --no-package-lock --omit=dev \
				--ignore-scripts --no-audit --no-fund >/dev/null 2>&1); then
			echo "  [FAIL] $name — cannot vendor the dependency tree" >&2
			return 1
		fi
	fi
	rm -rf "$vendor/$name.old"
	if [ -d "$vendor/$name" ]; then
		mv "$vendor/$name" "$vendor/$name.old"
	fi
	mv "$stage/tree" "$vendor/$name"
	fetched "$name" "$ver"
	rm -rf "$vendor/$name.old"
	echo "  $name: npm $pkg@$ver"
}

# resolve_git <url> <ref> — print "<kind> <sha> <name>" for a branch, a tag
# (annotated tags peel to their commit), or latest (newest tag by version
# sort; HEAD when the repo tags nothing). Prints nothing and fails on a
# dangling ref.
resolve_git() { # <url> <ref>
	url=$1 ref=$2
	ls=$(git ls-remote "$url" 2>/dev/null) || return 1
	case $ref in
	latest)
		# Newest version-looking tag, peel-aware; HEAD as the fallback.
		res=$(printf '%s\n' "$ls" | awk '
			$2 ~ /^refs\/tags\// {
				name = $2
				sub(/^refs\/tags\//, "", name)
				peel = (name ~ /\^\{\}$/)
				sub(/\^\{\}$/, "", name)
				if (peel || !(name in seen)) {
					seen[name] = 1
					print name "\t" $1
				}
			}' | sort -t"	" -k1,1V | tail -1)
		if [ -n "$res" ]; then
			printf 'tag %s %s\n' "${res#*	}" "${res%%	*}"
			return 0
		fi
		rsha=$(printf '%s\n' "$ls" | awk '$2 == "HEAD" {print $1}')
		[ -n "$rsha" ] && printf 'head %s HEAD\n' "$rsha"
		return
		;;
	esac
	# Branch, exact match.
	rsha=$(printf '%s\n' "$ls" | awk -v r="refs/heads/$ref" '$2 == r {print $1}')
	if [ -n "$rsha" ]; then
		printf 'branch %s %s\n' "$rsha" "$ref"
		return 0
	fi
	# Tag, exact match — the peeled ^{} line (an annotated tag's commit) comes
	# after the tag-object line, so it wins.
	rsha=$(printf '%s\n' "$ls" | awk -v r="refs/tags/$ref" '
		$2 == r {cand = $1}
		$2 == r "^{}" {cand = $1}
		END {print cand}')
	if [ -n "$rsha" ]; then
		printf 'tag %s %s\n' "$rsha" "$ref"
		return 0
	fi
	return 1
}

fetch_git() { # <name> <url> <ref: branch | tag | latest>
	name=$1 url=$2 ref=$3
	res=$(resolve_git "$url" "$ref")
	if [ -z "$res" ]; then
		echo "  [FAIL] $name — cannot resolve $ref on $url" >&2
		return 1
	fi
	kind=${res%% *}
	rsha=${res#* }; rsha=${rsha%% *}
	rname=${res##* }
	stage="$tmp/$name"
	mkdir -p "$stage"
	# Fetch by SHA through codeload so no checkout or .git ever lands here.
	case $url in
	https://github.com/*)
		slug=${url#https://github.com/}; slug=${slug%.git}
		curl -fsSL "https://codeload.github.com/$slug/tar.gz/$rsha" -o "$tmp/$name.tgz"
		tar xzf "$tmp/$name.tgz" -C "$stage"
		;;
	*)
		# Non-GitHub remotes: shallow clone, then drop .git.
		git clone --quiet --depth 1 --branch "$rname" "$url" "$stage/tree" 2>/dev/null
		rm -rf "$stage/tree/.git"
		;;
	esac
	rm -rf "$vendor/$name.old"
	if [ -d "$vendor/$name" ]; then
		mv "$vendor/$name" "$vendor/$name.old"
	fi
	mv "$stage"/*/ "$vendor/$name" 2>/dev/null || mv "$stage/tree" "$vendor/$name"
	fetched "$name" "$rname@$rsha"
	rm -rf "$vendor/$name.old"
	echo "  $name: git $url $kind $rname@$rsha"
}

mkdir -p "$vendor/.refs"
failed=0
while read -r name type url ref; do
	case $name in '' | '#'*) continue ;; esac
	printf 'refreshing %s\n' "$name"
	case $type in
	npm) fetch_npm "$name" "$url" "$ref" || failed=1 ;;
	git) fetch_git "$name" "$url" "$ref" || failed=1 ;;
	*)
		echo "  [FAIL] $name — unknown type '$type'" >&2
		failed=1
		;;
	esac
done <"$manifest"

if [ "$failed" -ne 0 ]; then
	echo "refresh finished with failures" >&2
	exit 1
fi
echo "refresh complete — vendor/ only; patches not applied"
