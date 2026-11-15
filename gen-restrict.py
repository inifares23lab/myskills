#!/usr/bin/env python3
"""Generate the provider model-restriction sections for opencode.json.

V2 has no provider whitelist: to show only some models you must set
"disabled": true on every other catalog model. This script rebuilds those
disable lists from the live catalog for the restricted providers.

Providers and keep rules:
  - zai:        keep glm-5.3 + glm-5.3-flash + any free models
  - opencode:   keep big-pickle + all free models
  - openrouter: keep only qwen/qwen3.8-27b:free

Usage:
    python3 gen-restrict.py > restrict.json

Then merge each provider's models map under `providers` in
~/.config/opencode/opencode.json (keep every existing key there).

Verify after merging:
    opencode api get /api/model   # counts per provider

Re-run whenever the catalog grows: new catalog models appear in /models unless
you disable them again here.
"""
import json
import subprocess
import sys
import tempfile

# provider -> explicit catalog model IDs to keep enabled
# zai free models (per Z.AI docs): glm-4.7-flash, glm-4.6-flash, glm-4.6v-flash.
# glm-4.6-flash is not in the OpenCode zai catalog, so it is also defined in
# opencode.json under providers.zai.models (this script only skips disabling it).
EXPLICIT_KEEP = {
    "zai": ["glm-5.3", "glm-5.3-flash", "glm-4.7-flash", "glm-4.6-flash", "glm-4.6v-flash"],
    "opencode": ["big-pickle"],
    "openrouter": ["qwen/qwen3.8-27b:free"],
}
# providers where every free model stays enabled too
KEEP_FREE = {"zai", "opencode"}


def is_free(m: dict) -> bool:
    mid = m.get("id") or ""
    name = m.get("name") or ""
    return ":free" in mid or "free" in name.lower()


def fetch_catalog() -> list:
    """Fetch the live model catalog from the local opencode server.

    Writes to a temp file instead of capturing stdout: the CLI response can be
    large enough to be truncated by the caller's pipe.
    """
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        path = f.name
    proc = subprocess.run(
        ["opencode", "api", "get", "/api/model"],
        stdout=open(path, "w"),
        stderr=subprocess.PIPE,
        text=True,
    )
    if proc.returncode != 0:
        sys.exit(f"failed to fetch catalog: {proc.stderr}")
    with open(path) as f:
        data = json.load(f)
    return data["data"] if isinstance(data, dict) else data


def main() -> None:
    models = fetch_catalog()
    out = {}
    for provider, keep in EXPLICIT_KEEP.items():
        ids = [m["id"] for m in models if m.get("providerID") == provider]
        keep_set = set(keep)
        if provider in KEEP_FREE:
            keep_set |= {m["id"] for m in models
                         if m.get("providerID") == provider and is_free(m)}
        for k in sorted(keep_set - set(ids)):
            print(
                f"warning: keep entry '{k}' not in current {provider} catalog; "
                f"leaving it untouched (re-run after the catalog syncs)",
                file=sys.stderr,
            )
        disabled = {mid: {"disabled": True} for mid in ids if mid not in keep_set}
        out.setdefault("providers", {})[provider] = {"models": disabled}
        print(
            f"# {provider}: {len(ids)} catalog models, keeping {sorted(keep_set)}",
            file=sys.stderr,
        )
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()