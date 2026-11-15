#!/usr/bin/env python
"""Laya intent gate (LAYA-RESEARCH.md §3.1).

Free text in -> gate decision + intent_manifest JSON out.
Exit 0 = PROCEED (manifest printed), exit 1 = CLARIFY.

Usage:
  python laya_gate.py "Replace JWT auth in src/auth.ts with HMAC sessions" \
      --scope src/auth.ts --non-goal "DB schema" --non-goal "user routes"

  python laya_gate.py --demo      # self-check: clear prompt proceeds, vague one halts
"""
import argparse
import json
import sys

GATE_THRESHOLD = 0.92          # scope_unambiguous must clear this (Jev-notes value)
DESTRUCTIVE_THRESHOLD = 0.80   # above this, warn but still proceed

QUESTIONS = {
    "change_type": {
        "type": "choice",
        "instructions": "What kind of software change does `raw_prompt` request?",
        "criteria": {
            "refactor": "restructure code without changing behaviour",
            "feature": "add new behaviour or capability",
            "bugfix": "fix behaviour that is broken",
            "chore": "tooling, deps, config, docs, cleanup",
            "out_of_scope": "not a software change, or cannot be told",
        },
    },
    "scope_unambiguous": {
        "type": "noul",
        "instructions": (
            "Is `raw_prompt` specific enough to execute without asking the user "
            "anything: it names a concrete target and a verifiable outcome?"
        ),
    },
    "destructive": {
        "type": "noul",
        "instructions": (
            "Does `raw_prompt` request destructive or hard-to-reverse operations "
            "(deleting data, dropping tables, force pushes, removing files)?"
        ),
    },
    "db_schema_touched": {
        "type": "noul",
        "instructions": "Does `raw_prompt` require changing a database schema or migrations?",
    },
}


def gate(agent, raw_prompt: str, scope: list[str], non_goals: list[str]) -> dict:
    state = {
        "raw_prompt": raw_prompt,
        "declared_scope": scope or ["(none declared)"],
        "declared_non_goals": non_goals or ["(none declared)"],
    }
    answers = agent.predict(state, QUESTIONS)["answers"]

    action = answers["change_type"]["choice"]
    unambiguous = answers["scope_unambiguous"]["noul"]
    destructive = answers["destructive"]["noul"]

    manifest = {
        "action": action,
        "target_scope": scope,
        "acceptance_criteria": [],
        "non_goals": non_goals,
        "raw_prompt": raw_prompt,
        "laya": {
            "db_schema_touched": answers["db_schema_touched"]["noul"],
            "destructive": destructive,
            "change_type_probabilities": answers["change_type"]["probabilities"],
        },
    }

    if action == "out_of_scope":
        return {"status": "CLARIFY", "reason": "not recognisable as a software change", "manifest": manifest}
    if unambiguous < GATE_THRESHOLD:
        return {
            "status": "CLARIFY",
            "reason": f"scope_unambiguous={unambiguous:.2f} < {GATE_THRESHOLD}; "
                      "ask for exact files and a verifiable outcome",
            "manifest": manifest,
        }
    if destructive > DESTRUCTIVE_THRESHOLD:
        manifest["requires_confirmation"] = True
    return {"status": "PROCEED", "reason": f"scope_unambiguous={unambiguous:.2f}", "manifest": manifest}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("prompt", nargs="?", help="raw user prompt")
    ap.add_argument("--scope", action="append", default=[], help="target path (repeatable)")
    ap.add_argument("--non-goal", action="append", default=[], help="exclusion (repeatable)")
    ap.add_argument("--demo", action="store_true", help="run the self-check")
    args = ap.parse_args()

    if args.demo:
        clear = gate(load_agent(), "Replace JWT verification in src/auth.ts with HMAC session checks, leave the DB untouched", ["src/auth.ts"], ["DB schema"])
        vague = gate(load_agent(), "make the login better somehow", [], [])
        assert clear["status"] == "PROCEED", clear
        assert vague["status"] == "CLARIFY", vague
        print("demo OK: clear -> PROCEED, vague -> CLARIFY")
        return 0

    if not args.prompt:
        ap.error("prompt required (or --demo)")

    result = gate(load_agent(), args.prompt, args.scope, args.non_goal)
    print(json.dumps(result, indent=2))
    return 0 if result["status"] == "PROCEED" else 1


_agent = None
def load_agent():
    global _agent  # reuse across --demo's two calls; one load per process
    if _agent is None:
        import torch
        import laya
        device = "cuda" if torch.cuda.is_available() else "cpu"
        _agent = laya.load("convaiinnovations/laya", device=device)
    return _agent


if __name__ == "__main__":
    sys.exit(main())
