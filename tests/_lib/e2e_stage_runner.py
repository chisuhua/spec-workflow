#!/usr/bin/env python3
# tests/_lib/e2e_stage_runner.py
#
# Helper for E2E test fixture: emits stage handoff JSON to .rddf/state/
# using env-var passing (Oracle C1 safe, per AGENTS.md §20).
#
# Why self-contained (does NOT call skills.rdd-arch/scripts/write_arch_handoff.py):
#   - Decouples E2E from library signature drift (function signature, schema_version)
#   - test_v4_e2e_3_stage_flow.bats covers the Python API path
#   - This helper covers CLI entry + JSON schema shape only
#
# Required env vars:
#   E2E_STAGE          — one of: arch | planner | builder
#   E2E_PROJECT_ROOT   — absolute path to fake project root
#   E2E_CHANGE_NAME    — change name (for builder stage)
#
# Returns: exit 0 on success, non-zero on gate failure.

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


def _get(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def _state_path(project_root: str, filename: str) -> Path:
    p = Path(project_root) / ".rddf" / "state" / filename
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


def stage_arch() -> int:
    """Emit .arch-handoff.json (v3 schema per ADR-0016, schema_version key).

    Self-contained shape mirrors the contract validated by rdd-arch consumers:
      top-level keys: schema_version, arch_complete_at, arch_complete_revision,
                      adr_count, completed_adr_ids, current_phase, plan_started_at,
                      adr_dir, architecture_dir, adr_pattern, discovered
    """
    project_root = _get("E2E_PROJECT_ROOT")
    if not project_root:
        print("ERROR: E2E_PROJECT_ROOT not set", file=sys.stderr)
        return 1

    adr_dir = _get("E2E_ADR_DIR", "docs/adr")
    adr_files = sorted(Path(project_root).glob(f"{adr_dir}/ADR-*.md"))
    if not adr_files:
        print(
            f"❌ arch gate: no ADR-*.md found in {project_root}/{adr_dir}/",
            file=sys.stderr,
        )
        return 10

    completed_adr_ids = []
    for f in adr_files:
        stem = f.stem
        parts = stem.split("-", 2)
        if len(parts) >= 2 and parts[0] == "ADR":
            completed_adr_ids.append(parts[1])

    roadmap_path = Path(project_root) / _get("E2E_ROADMAP_PATH", "roadmap.md")
    current_phase = "phase-1"
    if roadmap_path.exists():
        for line in roadmap_path.read_text().splitlines():
            if "**当前阶段**" in line and ":" in line:
                current_phase = line.split(":", 1)[1].strip()
                break

    now = datetime.now(timezone.utc).isoformat()
    handoff = {
        "schema_version": 3,
        "arch_complete_at": now,
        "arch_complete_revision": 1,
        "adr_count": len(adr_files),
        "completed_adr_ids": completed_adr_ids,
        "current_phase": current_phase,
        "plan_started_at": None,
        "adr_dir": adr_dir,
        "architecture_dir": _get("E2E_ARCHITECTURE_DIR", "docs/architecture"),
        "adr_pattern": _get("E2E_ADR_PATTERN", "ADR-*.md"),
        "discovered": {
            "adr_dir": {"found": True, "created": False, "candidates_tried": 3},
            "architecture_dir": {"found": False, "created": False, "candidates_tried": 3},
            "roadmap_path": {"found": True, "created": False, "candidates_tried": 2},
        },
    }

    out = _state_path(project_root, ".arch-handoff.json")
    out.write_text(json.dumps(handoff, indent=2, ensure_ascii=False))
    return 0


def stage_planner() -> int:
    """Emit .planner-handoff.json (v1 schema per spec §3.3)."""
    project_root = _get("E2E_PROJECT_ROOT")
    if not project_root:
        print("ERROR: E2E_PROJECT_ROOT not set", file=sys.stderr)
        return 1

    handoff = {
        "schema_version": 1,
        "owner": "rdd-planner",
        "source_arch_handoff": f"{project_root}/.rddf/state/.arch-handoff.json",
        "discovered_roadmap_path": "roadmap.md",
        "phases_completed": ["entry", "exit"],
    }
    out = _state_path(project_root, ".planner-handoff.json")
    out.write_text(json.dumps(handoff, indent=2))
    return 0


def stage_builder() -> int:
    """Emit .rddf/state/builder/<change>.json (per-change handoff)."""
    project_root = _get("E2E_PROJECT_ROOT")
    change_name = _get("E2E_CHANGE_NAME")
    if not project_root or not change_name:
        print("ERROR: E2E_PROJECT_ROOT and E2E_CHANGE_NAME required", file=sys.stderr)
        return 1

    handoff = {
        "schema_version": 1,
        "change": change_name,
        "owner": "rdd-builder",
        "phases_completed": ["P0_approval", "P1_plan", "P1_5_deps", "P2_execute"],
        "execution_mode": "lightweight",
        "worktree_commits": 1,
    }
    out = _state_path(project_root, f"builder/{change_name}.json")
    out.write_text(json.dumps(handoff, indent=2))
    return 0


_STAGES = {
    "arch": stage_arch,
    "planner": stage_planner,
    "builder": stage_builder,
}


def main() -> int:
    stage = _get("E2E_STAGE")
    fn = _STAGES.get(stage)
    if fn is None:
        print(f"ERROR: unknown E2E_STAGE={stage!r}", file=sys.stderr)
        return 2
    return fn()


if __name__ == "__main__":
    sys.exit(main())
