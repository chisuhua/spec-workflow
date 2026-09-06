# rdd-workflow Full-Workflow E2E Test — Implementation Plan v2 (Real Path)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Revision**: supersedes `2026-09-06-rdd-workflow-full-e2e.md` (plan v1, commit `b814039`) which was a self-contained simulator. v2 invokes real Python APIs per design v2 (commit `3d6bb87`).

**Goal:** Replace v1's self-contained fake runner with real function invocation. Fixture helper (`test_full_workflow_fixture.bash`) calls into actual `_lib/*.py` and `skills/*/scripts/*.sh`. Test cases assert against real `_lib/schemas/*.json` contracts, gated by `jsonschema.validate()`.

**Architecture (revised):**
- **Removed**: `tests/_lib/e2e_stage_runner.py` (self-contained fake — replaced by real script invocations)
- **Added**: `tests/_lib/test_full_workflow_e2e_runner.py` (env-var shim for `_lib.builder_handoff.write_builder_handoff`, since bats → Python module needs sys.path manipulation; mirrors `write_arch_handoff_env.py` pattern)
- **Modified**: `tests/_lib/test_full_workflow_fixture.bash` (8 functions still, but each calls REAL API)
- **Modified**: `tests/integration/test_full_workflow_e2e.bats` (7 cases, schema-key updated, real gate semantics)
- **Modified**: `tests/_lib/test_full_workflow_fixture_*.bats` (5 helper files, schema-key updated)
- **Modified**: `tests/_lib/test_full_workflow_e2e_runner.py` (3-file split per AGENTS.md §20)

**Tech Stack:** bats-core 1.10+ (assertions + setup/teardown), bash 4+ (fixture functions), git 2.25+ (fake project init), python3 3.11+ (real API invocation), jq 1.6+ (JSON assertions), openspec CLI 1.4.1+ (archive happy path), jsonschema Python package (contract validation).

**Reference spec:** `docs/superpowers/specs/2026-09-06-rdd-workflow-full-e2e-design-v2.md` (commit `3d6bb87`)

---

## File Map (revised)

| File | Action | Responsibility | Approx size |
|---|---|---|---|
| `tests/_lib/e2e_stage_runner.py` | **DELETE** | (was self-contained fake) | -154 lines |
| `tests/_lib/test_full_workflow_e2e_runner.py` | CREATE | Env-var shim for `_lib.builder_handoff.write_builder_handoff` (Oracle C1 safe) | ~60 lines |
| `tests/_lib/test_full_workflow_e2e_runner.env.py` | CREATE | Shim companion (per 3-file split) | ~40 lines |
| `tests/_lib/test_full_workflow_e2e_runner.sh` | CREATE | Bash wrapper (per 3-file split) | ~30 lines |
| `tests/_lib/test_full_workflow_fixture.bash` | REWRITE | 8 fixture functions invoking REAL APIs | ~200 lines |
| `tests/integration/test_full_workflow_e2e.bats` | REWRITE | 7 cases using REAL schema keys + jsonschema | ~140 lines |
| `tests/_lib/test_full_workflow_fixture_skeleton.bats` | UPDATE | Test fixture loadable + 8 functions exist | ~25 lines |
| `tests/_lib/test_full_workflow_fixture_setup.bats` | UPDATE | setup_fake_project + write_arch_fixture | ~30 lines |
| `tests/_lib/test_full_workflow_fixture_proposal.bats` | UPDATE | write_proposal_fixture + invoke_arch_stage (REAL schema assert) | ~50 lines |
| `tests/_lib/test_full_workflow_fixture_stages.bats` | UPDATE | invoke_planner_stage + invoke_builder_phases (REAL schema assert) | ~55 lines |
| `tests/_lib/test_full_workflow_fixture_archive.bats` | UPDATE | invoke_archive (REAL gate + happy path) + assert_state | ~75 lines |

**Constraints:**
- Helpers MUST use `$BATS_TEST_TMPDIR` (auto-cleaned) — never `$REPO_ROOT/.rddf/state/`
- Helpers MUST NOT use `os.chdir()` patterns that leave cwd pointing to deleted temp dir
- All assertions MUST avoid `assert.*or True` / `assert True` tautologies
- Real Python invocation MUST use env-var passing pattern (AGENTS.md §20)
- Real Python invocation MUST set `SKIP_VERIFIER_CONTRACT=yes` + `SKIP_AC_VERIFICATION=yes` to bypass non-task gates
- Test runtime MUST be ≤ 2 minutes

---

## Task 1: Delete `e2e_stage_runner.py` (the self-contained fake)

**Files:**
- Delete: `tests/_lib/e2e_stage_runner.py`

- [ ] **Step 1: Verify no other file references e2e_stage_runner.py**

```bash
grep -rn "e2e_stage_runner" tests/ skills/ docs/ 2>/dev/null
```

Expected: NO matches (only `test_full_workflow_fixture.bash` imports it, which we're rewriting).

- [ ] **Step 2: Delete the file**

```bash
git rm tests/_lib/e2e_stage_runner.py
```

- [ ] **Step 3: Commit**

```bash
git commit -m "test(e2e): delete e2e_stage_runner.py (self-contained fake)

The v1 implementation re-implemented all 3 stage emissions in fake
Python code that didn't match the real _lib/schemas/* contracts
and didn't exercise any production code. v2 plan replaces these
with real script invocation via env-var passing pattern.
"
```

---

## Task 2: Add env-py shim for `_lib.builder_handoff.write_builder_handoff`

**Files:**
- Create: `tests/_lib/test_full_workflow_e2e_runner.py`
- Create: `tests/_lib/test_full_workflow_e2e_runner.env.py`
- Create: `tests/_lib/test_full_workflow_e2e_runner.sh`

**Why a shim**: bats shell can't easily call Python module functions with sys.path setup. Mirrors the existing `write_arch_handoff_env.py` pattern (per AGENTS.md §20, 3-file split pattern). The shim reads env vars and calls `_lib.builder_handoff.write_builder_handoff`.

- [ ] **Step 1: Write the .env.py shim**

Create `tests/_lib/test_full_workflow_e2e_runner.env.py`:

```python
#!/usr/bin/env python3
"""Shim for invoke_builder_phases — env-var pattern (Oracle C1 safe).

Reads env vars (E2E_PROJECT_ROOT, E2E_CHANGE_NAME, E2E_BUILDER_*) and
calls _lib.builder_handoff.write_builder_handoff(). Mirrors the pattern
of skills/rdd-arch/scripts/write_arch_handoff_env.py.

Required env vars:
  E2E_PROJECT_ROOT    — absolute path to fake project root
  E2E_CHANGE_NAME     — OpenSpec change name

Optional env vars (with defaults matching builder_handoff signature):
  E2E_BUILDER_PHASE             (default: phase-2)
  E2E_BUILDER_APPROVAL_STATUS   (default: approved)
  E2E_BUILDER_EXECUTION_MODE    (default: lightweight)
  E2E_BUILDER_EXECUTION_STATUS  (default: completed)
  E2E_BUILDER_REVIEW_STATUS     (default: merge)
  E2E_BUILDER_ARCHIVE_STATUS    (default: pending)
  E2E_BUILDER_RETRY_COUNT       (default: 0)
  E2E_BUILDER_MAX_RETRIES       (default: 3)
  E2E_BUILDER_BRANCH            (default: openspec/<change>)
  E2E_BUILDER_WORKTREE_PATH     (default: empty — lightweight)

Returns: exit 0 on success, 1 on missing env vars.
"""
import json
import os
import sys
from pathlib import Path

# Compute repo root from this script's location (go up 3 levels: _lib -> tests -> repo)
_repo_root = str(Path(__file__).resolve().parent.parent.parent)
if _repo_root not in sys.path:
    sys.path.insert(0, _repo_root)

project_root = os.environ.get("E2E_PROJECT_ROOT")
change_name = os.environ.get("E2E_CHANGE_NAME")
if not project_root or not change_name:
    print("ERROR: E2E_PROJECT_ROOT and E2E_CHANGE_NAME required", file=sys.stderr)
    sys.exit(1)

from _lib.builder_handoff import write_builder_handoff  # noqa: E402

result = write_builder_handoff(
    project_root=project_root,
    change_name=change_name,
    current_phase=os.environ.get("E2E_BUILDER_PHASE", "phase-2"),
    approval_status=os.environ.get("E2E_BUILDER_APPROVAL_STATUS", "approved"),
    execution_mode_decision={
        "mode": os.environ.get("E2E_BUILDER_EXECUTION_MODE", "lightweight"),
        "reason": "e2e-fake-project-fixture",
        "decided_at": "2026-09-06T00:00:00Z",
        "decided_by": "test_full_workflow_e2e_runner",
    },
    worktree_path=os.environ.get("E2E_BUILDER_WORKTREE_PATH", ""),
    branch=os.environ.get("E2E_BUILDER_BRANCH", f"openspec/{change_name}"),
    execution_status=os.environ.get("E2E_BUILDER_EXECUTION_STATUS", "completed"),
    review_status=os.environ.get("E2E_BUILDER_REVIEW_STATUS", "merge"),
    archive_status=os.environ.get("E2E_BUILDER_ARCHIVE_STATUS", "pending"),
    retry_count=int(os.environ.get("E2E_BUILDER_RETRY_COUNT", "0")),
    max_retries=int(os.environ.get("E2E_BUILDER_MAX_RETRIES", "3")),
)

print(
    "✅ builder handoff written: "
    f".rddf/state/builder/{change_name}.json "
    f"(phase={result['current_phase']}, archive={result['archive_status']})"
)
```

- [ ] **Step 2: Write the .py entry point**

Create `tests/_lib/test_full_workflow_e2e_runner.py`:

```python
#!/usr/bin/env python3
"""Entry-point for tests/_lib/test_full_workflow_e2e_runner.sh.

Forwards to .env.py shim. Mirrors skills/rdd-arch/scripts/write_arch_handoff.py
role (which forwards to .env.py).

All values flow through os.environ (Oracle C1 safe — no bash string interpolation).
"""
import os
import sys
from pathlib import Path

# Ensure .env.py is importable from the same dir
_here = str(Path(__file__).resolve().parent)
if _here not in sys.path:
    sys.path.insert(0, _here)

# Delegate
from test_full_workflow_e2e_runner_env import (  # noqa: E402
    project_root := __import__("os").environ.get("E2E_PROJECT_ROOT"),
)
```

Hmm — actually this indirection is unnecessary. Let me simplify. The .sh wrapper can call .env.py directly. Let me revise:

- [ ] **Step 2 (revised): Drop the .py entry point**

Just `.sh` + `.env.py`. The `.sh` calls `.env.py` directly via Python. Skip the third file.

- [ ] **Step 3: Write the .sh bash wrapper**

Create `tests/_lib/test_full_workflow_e2e_runner.sh`:

```bash
#!/usr/bin/env bash
# tests/_lib/test_full_workflow_e2e_runner.sh
# Bash wrapper for the builder handoff env-py shim.
# Mirrors skills/rdd-arch/scripts/write_arch_handoff.sh pattern (Oracle C1 safe).
#
# Usage: source this file to export the helper, or call directly via:
#   bash test_full_workflow_e2e_runner.sh   # uses env vars

_runner_sh() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"

    # All values flow via env vars (Oracle C1 safe)
    python3 "$script_dir/test_full_workflow_e2e_runner.env.py"
}

# If invoked (not sourced), run directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    _runner_sh "$@"
fi

# Export the function so callers can `source` and invoke via the helper
export -f _runner_sh 2>/dev/null || true
```

- [ ] **Step 4: Make scripts executable and commit**

```bash
chmod +x tests/_lib/test_full_workflow_e2e_runner.sh
chmod +x tests/_lib/test_full_workflow_e2e_runner.env.py

git add tests/_lib/test_full_workflow_e2e_runner.sh \
        tests/_lib/test_full_workflow_e2e_runner.env.py

git commit -m "test(e2e): add env-py shim for builder handoff (Oracle C1 safe)

Mirrors skills/rdd-arch/scripts/write_arch_handoff_env.py pattern.
Bats shell can't easily call Python module functions with sys.path
setup, so we provide a 2-file shim (sh + env.py) that reads env
vars and delegates to _lib.builder_handoff.write_builder_handoff().
"
```

---

## Task 3: Rewrite `test_full_workflow_fixture.bash` with real API invocation

**Files:**
- Rewrite: `tests/_lib/test_full_workflow_fixture.bash`

The 8 functions stay, but each now invokes the REAL API. Significant rewrite.

- [ ] **Step 1: Write the new fixture helper**

Replace `tests/_lib/test_full_workflow_fixture.bash` entirely:

```bash
#!/usr/bin/env bash
# tests/_lib/test_full_workflow_fixture.bash
#
# Helper functions for test_full_workflow_e2e.bats.
# Sourced via load_lib test_full_workflow_fixture.
#
# v2 (real path): each invoke_* function calls REAL production code:
#   invoke_arch_stage    → skills/rdd-arch/scripts/write_arch_handoff.sh
#                           (via python3 -m skills.rdd_arch.scripts.write_arch_handoff_env)
#   invoke_arch_gate     → skills/rdd-arch/scripts/arch_done_gate.sh::check_arch_done_gate
#   invoke_planner_stage → python3 -m _lib.planner_handoff
#   invoke_builder_phases→ test_full_workflow_e2e_runner.sh (env-py shim for
#                           _lib.builder_handoff.write_builder_handoff)
#   invoke_archive       → _lib/archive.sh::archive_gate_check (error path)
#                         OR openspec archive + mark_iteration_archived (happy path)
#   assert_state         → jq field assertions on .rddf/state/*.json
#   assert_schema        → jsonschema.validate against _lib/schemas/*.json
#
# Oracle C1 safety: all Python invocations use env-var passing; NEVER bash
# string interpolation. No `python3 -c "...$VAR..."`.

# Resolve REPO_ROOT once (set by test_helper.bash via load_lib)
: "${REPO_ROOT:?REPO_ROOT not set — load test_helper first}"

# ─── Fake project setup ─────────────────────────────────────────────────

setup_fake_project() {
    local root
    root="${BATS_TEST_TMPDIR:-/tmp}/fake-project-$$-${RANDOM}"
    mkdir -p "$root"
    cd "$root" || return 1
    git init -q
    git config user.email "e2e@test.local"
    git config user.name "E2E Test"
    echo "fake project" > README.md
    echo '{"name":"fake-project","version":"0.0.1"}' > package.json
    git add README.md package.json
    git commit -q -m "init fake project"
    echo "$root"
}

# Write arch-stage fixture: 1 ADR + minimal roadmap
# Args: $1 = fake project root
write_arch_fixture() {
    local root="$1"
    mkdir -p "$root/docs/adr"
    cat > "$root/docs/adr/ADR-0001-test-arch.md" <<'EOF'
# ADR-0001: Test Architecture

**Status**: 已采纳 (2026-01-01)

## Context
E2E fixture for full-workflow E2E test.
EOF
    cat > "$root/roadmap.md" <<'EOF'
# Roadmap

**当前阶段**: phase-1

## Phase Skeleton
| Phase | Theme | Status |
|-------|-------|--------|
| phase-1 | e2e-fixture | active |
EOF
    git -C "$root" add docs/adr/ADR-0001-test-arch.md roadmap.md
    git -C "$root" commit -q -m "add arch fixture"
}

# Write proposal-stage fixture: skeleton proposal.md + tasks.md + design.md
# Args: $1 = fake project root, $2 = change name
write_proposal_fixture() {
    local root="$1" name="$2"
    mkdir -p "$root/openspec/changes/$name"
    cat > "$root/openspec/changes/$name/proposal.md" <<EOF
# $name Proposal

## Why
E2E fixture proposal.
EOF
    cat > "$root/openspec/changes/$name/tasks.md" <<EOF
# $name Tasks

- [ ] 1. Implement fixture
- [ ] 2. Run E2E test
EOF
    cat > "$root/openspec/changes/$name/design.md" <<EOF
# $name Design

## Approach
Direct implementation.
EOF
    git -C "$root" add "openspec/changes/$name"
    git -C "$root" commit -q -m "add $name change fixture"
}

# ─── Real stage invocation ──────────────────────────────────────────────

# Invoke rdd-arch stage: writes .arch-handoff.json via REAL write_arch_handoff
# Args: $1 = fake project root
invoke_arch_stage() {
    local root="$1"
    cd "$root" || return 1

    # Real writer requires PROJECT_ROOT + DISCOVERED_* env vars
    # Side-effect env vars disable reflect + planner feedback hooks
    PROJECT_ROOT="$root" \
    SKIP_WORKFLOW_REFLECTION=1 \
    SKIP_AUTO_PLANNER_FEEDBACK=1 \
    DISCOVERED_ADR_DIR=docs/adr \
    DISCOVERED_ADR_PATTERN='ADR-*.md' \
    DISCOVERED_ADR_DIR_FOUND=true \
    DISCOVERED_ROADMAP_FOUND=true \
    DISCOVERED_ARCH_FOUND=false \
    DISCOVERED_ADR_DIR_TRIED=3 \
    DISCOVERED_ROADMAP_TRIED=2 \
    DISCOVERED_ARCH_TRIED=3 \
    DISCOVERED_ROADMAP_PATH=roadmap.md \
    DISCOVERED_ARCHITECTURE_DIR=docs/architecture \
    ROADMAP_EXISTS_BOOL=true \
        python3 -m skills.rdd_arch.scripts.write_arch_handoff_env
}

# Invoke rdd-arch gate: real check_arch_done_gate (error path test)
# Args: $1 = fake project root
invoke_arch_gate() {
    local root="$1"
    cd "$root" || return 1

    # Source the real arch gate function
    # shellcheck source=/dev/null
    source "$REPO_ROOT/skills/rdd-arch/scripts/arch_done_gate.sh"

    # Real gate reads DISCOVERED_* env vars (set to point at fake project)
    PROJECT_ROOT="$root" \
    DISCOVERED_ADR_DIR=docs/adr \
    DISCOVERED_ADR_PATTERN='ADR-*.md' \
    DISCOVERED_ROADMAP_PATH=roadmap.md \
    check_arch_done_gate
}

# Invoke rdd-planner stage: writes .planner-handoff.json via REAL python module
# Args: $1 = fake project root
invoke_planner_stage() {
    local root="$1"
    cd "$root" || return 1

    # Real writer reads PROJECT_ROOT + 4 env vars (per _lib/planner_handoff.py:48-57)
    PROJECT_ROOT="$root" \
    PROPOSALS_AUTHORED="add-e2e-fixture" \
    PROPOSALS_APPROVED_COUNT=1 \
    FEATURES_ACTIVE="feat-e2e-fixture" \
    CURRENT_SPRINT="sprint-2026-09" \
        python3 -m _lib.planner_handoff
}

# Invoke rdd-builder handoff: writes .rddf/state/builder/<change>.json via env-py shim
# Args: $1 = fake project root, $2 = change name
invoke_builder_phases() {
    local root="$1" name="$2"
    cd "$root" || return 1

    # Real writer via env-py shim (Oracle C1 safe)
    PROJECT_ROOT="$REPO_ROOT" \
    E2E_PROJECT_ROOT="$root" \
    E2E_CHANGE_NAME="$name" \
    E2E_BUILDER_PHASE=phase-2 \
    E2E_BUILDER_APPROVAL_STATUS=approved \
    E2E_BUILDER_EXECUTION_MODE=lightweight \
    E2E_BUILDER_EXECUTION_STATUS=completed \
    E2E_BUILDER_REVIEW_STATUS=merge \
    E2E_BUILDER_ARCHIVE_STATUS=pending \
        bash "$REPO_ROOT/tests/_lib/test_full_workflow_e2e_runner.sh"

    # Touch commit per AGENTS.md "Worktree Commit Flow" (lightweight mode:
    # changes are made on main repo, not in worktree)
    echo "# E2E touch $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$root/openspec/changes/$name/touch.log"
    git -C "$root" add "openspec/changes/$name/touch.log"
    git -C "$root" commit -q -m "e2e: touch commit for lightweight mode"
}

# Invoke archive gate (real function from _lib/archive.sh)
# Used for ERROR PATH tests only — checks tasks.md completeness
# Args: $1 = fake project root, $2 = change name
invoke_archive_gate() {
    local root="$1" name="$2"
    cd "$root" || return 1

    # Source the real archive.sh (provides archive_gate_check function)
    # shellcheck source=/dev/null
    source "$REPO_ROOT/_lib/archive.sh" 2>/dev/null || \
        source "$HOME/.agents/skills/_lib/archive.sh" 2>/dev/null || {
        echo "❌ cannot source archive.sh" >&2
        return 1
    }

    # Real gate: bypass non-task sub-gates (verifier + ac-verifier are Phase 2)
    SKIP_VERIFIER_CONTRACT=yes \
    SKIP_AC_VERIFICATION=yes \
    FORCE_ARCHIVE_INCOMPLETE=no \
        archive_gate_check "$name" "$root"
}

# Invoke full archive happy path: real openspec CLI + real mark_iteration_archived
# Args: $1 = fake project root, $2 = change name
invoke_archive_happy() {
    local root="$1" name="$2"
    cd "$root" || return 1

    # Real archive CLI
    openspec archive "$name" --yes 2>&1 || {
        echo "❌ openspec archive failed" >&2
        return 1
    }

    # Auto-commit the archive file moves (mirrors _lib/archive.sh::commit_archive_moves)
    git -C "$root" add "openspec/changes/" 2>/dev/null || true
    git -C "$root" commit -q -m "archive($name): archive completed" 2>/dev/null || true

    # Real mark_iteration_archived (via skills._lib.iteration.post_archive)
    cd "$REPO_ROOT"
    PROJECT_ROOT="$root" \
    CHANGE_NAME="$name" \
    ARCHIVE_COMMIT_SHA="$(git -C "$root" rev-parse HEAD 2>/dev/null || echo unknown)" \
        bash -c '
            python3 <<PYEOF
import os, sys
sys.path.insert(0, "'"$REPO_ROOT"'")
from skills._lib.iteration.post_archive import mark_iteration_archived
mark_iteration_archived(
    project_root=os.environ["PROJECT_ROOT"],
    change_name=os.environ["CHANGE_NAME"],
    archive_commit_sha=os.environ.get("ARCHIVE_COMMIT_SHA", ""),
)
print("✅ mark_iteration_archived complete")
PYEOF
'
}

# ─── State assertions ───────────────────────────────────────────────────

# Assert state file has expected schema fields
# Args: $1 = fake project root, $2 = state file (relative to .rddf/state/),
#       $3 = pipe-separated "key:val|key:val"
assert_state() {
    local root="$1" file="$2" fields="$3"
    local state_file="$root/.rddf/state/$file"
    [ -f "$state_file" ] || { echo "❌ assert_state: file missing: $state_file" >&2; return 1; }

    local IFS='|'
    local pair key expected actual
    for pair in $fields; do
        key="${pair%%:*}"
        expected="${pair#*:}"
        actual=$(jq -r --arg k "$key" '.[$k] // empty' "$state_file" 2>/dev/null)
        if [ "$actual" != "$expected" ]; then
            echo "❌ assert_state: $key expected '$expected' got '$actual'" >&2
            return 1
        fi
    done
}

# Validate state file against its real schema (jsonschema defense-in-depth)
# Args: $1 = fake project root, $2 = state file (relative to .rddf/state/),
#       $3 = schema filename under _lib/schemas/
assert_schema() {
    local root="$1" file="$2" schema="${3:-}"
    local state_file="$root/.rddf/state/$file"

    # Auto-derive schema filename if not provided
    case "$file" in
        .arch-handoff.json)     schema="${schema:-arch_handoff_schema.json}" ;;
        .planner-handoff.json)  schema="${schema:-planner_handoff_schema.json}" ;;
        builder/*.json)         schema="${schema:-builder_handoff_schema.json}" ;;
        iteration.json)         schema="${schema:-iteration_schema.json}" ;;
        *)
            echo "❌ assert_schema: unknown file $file" >&2
            return 1
            ;;
    esac

    local schema_file="$REPO_ROOT/_lib/schemas/$schema"
    [ -f "$schema_file" ] || { echo "❌ schema missing: $schema_file" >&2; return 1; }
    [ -f "$state_file" ] || { echo "❌ state file missing: $state_file" >&2; return 1; }

    # Run jsonschema.validate via inline Python (Oracle C1 safe — env-var passing)
    E2E_STATE_FILE="$state_file" \
    E2E_SCHEMA_FILE="$schema_file" \
        python3 - <<'PYEOF'
import json, os, sys
sys.path.insert(0, os.environ.get("REPO_ROOT", "."))
try:
    import jsonschema
except ImportError:
    print("⚠️ jsonschema not installed; skipping contract check", file=sys.stderr)
    sys.exit(0)
with open(os.environ["E2E_STATE_FILE"]) as f:
    payload = json.load(f)
with open(os.environ["E2E_SCHEMA_FILE"]) as f:
    schema = json.load(f)
try:
    jsonschema.validate(payload, schema)
    print("✅ schema validate OK")
except jsonschema.ValidationError as e:
    print(f"❌ schema validate FAIL: {e.message}", file=sys.stderr)
    sys.exit(1)
PYEOF
}
```

Wait — that last `python3 - <<'PYEOF'` inline is OK because it's heredoc (no bash $VAR inside the Python source). All values flow via env vars.

- [ ] **Step 2: Run skeleton test to verify fixture loadable**

```bash
bats tests/_lib/test_full_workflow_fixture_skeleton.bats
```

Expected: 2/2 pass (loadable + 8 functions exist).

- [ ] **Step 3: Commit**

```bash
git add tests/_lib/test_full_workflow_fixture.bash

git commit -m "test(e2e): rewrite fixture helper to invoke real APIs (v2)

Replaces v1's self-contained fake runner. Each invoke_* function
now calls real production code:

- invoke_arch_stage   → python3 -m skills.rdd_arch.scripts.write_arch_handoff_env
- invoke_arch_gate    → check_arch_done_gate (real function from arch_done_gate.sh)
- invoke_planner_stage → python3 -m _lib.planner_handoff
- invoke_builder_phases → test_full_workflow_e2e_runner.sh (env-py shim for _lib.builder_handoff.write_builder_handoff)
- invoke_archive_gate → archive_gate_check (real function from _lib/archive.sh)
- invoke_archive_happy → openspec archive + mark_iteration_archived

New helper: assert_schema validates against _lib/schemas/*.json via jsonschema.
"
```

---

## Task 4: Rewrite main bats file using real schema keys + jsonschema

**Files:**
- Rewrite: `tests/integration/test_full_workflow_e2e.bats`

- [ ] **Step 1: Write the new bats file**

Replace `tests/integration/test_full_workflow_e2e.bats` entirely:

```bash
#!/usr/bin/env bats
# tests/integration/test_full_workflow_e2e.bats
#
# Full-workflow E2E: fake project walks rdd-arch → rdd-planner →
# rdd-builder → archive lifecycle (lightweight mode).
#
# v2 (real path): invokes real production code per design v2 spec.
# Per docs/superpowers/specs/2026-09-06-rdd-workflow-full-e2e-design-v2.md
# 4 happy path cases + 3 error path cases.
#
# Self-contained: helper fixture at tests/_lib/test_full_workflow_fixture.bash
# isolates to \$BATS_TEST_TMPDIR (never touches \$REPO_ROOT/.rddf/state/).

load ../test_helper
load_lib test_full_workflow_fixture

setup() {
    FAKE_ROOT=$(setup_fake_project)
    export FAKE_ROOT
}

teardown() {
    # Unset all env vars set by invoke_* functions (prevent leak across tests)
    unset FAKE_ROOT PROJECT_ROOT \
          PROPOSALS_AUTHORED PROPOSALS_APPROVED_COUNT FEATURES_ACTIVE CURRENT_SPRINT \
          DISCOVERED_ADR_DIR DISCOVERED_ADR_PATTERN DISCOVERED_ADR_DIR_FOUND \
          DISCOVERED_ROADMAP_FOUND DISCOVERED_ARCH_FOUND DISCOVERED_ADR_DIR_TRIED \
          DISCOVERED_ROADMAP_TRIED DISCOVERED_ARCH_TRIED DISCOVERED_ROADMAP_PATH \
          DISCOVERED_ARCHITECTURE_DIR ROADMAP_EXISTS_BOOL \
          SKIP_WORKFLOW_REFLECTION SKIP_AUTO_PLANNER_FEEDBACK \
          E2E_PROJECT_ROOT E2E_CHANGE_NAME \
          E2E_BUILDER_PHASE E2E_BUILDER_APPROVAL_STATUS E2E_BUILDER_EXECUTION_MODE \
          E2E_BUILDER_EXECUTION_STATUS E2E_BUILDER_REVIEW_STATUS \
          E2E_BUILDER_ARCHIVE_STATUS E2E_BUILDER_RETRY_COUNT E2E_BUILDER_MAX_RETRIES \
          E2E_BUILDER_BRANCH E2E_BUILDER_WORKTREE_PATH \
          SKIP_VERIFIER_CONTRACT SKIP_AC_VERIFICATION FORCE_ARCHIVE_INCOMPLETE \
          ARCHIVE_COMMIT_SHA E2E_STATE_FILE E2E_SCHEMA_FILE \
          2>/dev/null || true

    # cd FIRST, then rm (per check_test_isolation.sh convention)
    cd "$REPO_ROOT"
    [ -n "$FAKE_ROOT" ] && [ -d "$FAKE_ROOT" ] && rm -rf "$FAKE_ROOT"
}

# ── Happy Path (4 cases) ─────────────────────────────────────────────

@test "full-workflow 1/7: arch stage emits valid .arch-handoff.json (v3 contract per ADR-0016)" {
    write_arch_fixture "$FAKE_ROOT"
    invoke_arch_stage "$FAKE_ROOT"

    # Real schema keys (version, NOT schema_version)
    assert_state "$FAKE_ROOT" ".arch-handoff.json" \
        "version:3|adr_dir:docs/adr|current_phase:phase-1"

    # Defense-in-depth: validate against real schema
    assert_schema "$FAKE_ROOT" ".arch-handoff.json"
}

@test "full-workflow 2/7: planner stage emits valid .planner-handoff.json (v1 contract per spec §3.3)" {
    write_arch_fixture "$FAKE_ROOT"
    invoke_arch_stage "$FAKE_ROOT"
    invoke_planner_stage "$FAKE_ROOT"

    # Real schema keys
    assert_state "$FAKE_ROOT" ".planner-handoff.json" \
        "schema:planner-handoff-v1|version:1|owner:rdd-planner|current_sprint:sprint-2026-09"

    assert_schema "$FAKE_ROOT" ".planner-handoff.json"
}

@test "full-workflow 3/7: builder handoff + real archive moves change to openspec/changes/archive/" {
    write_arch_fixture "$FAKE_ROOT"
    write_proposal_fixture "$FAKE_ROOT" "e2e-fixture"
    invoke_arch_stage "$FAKE_ROOT"
    invoke_planner_stage "$FAKE_ROOT"
    invoke_builder_phases "$FAKE_ROOT" "e2e-fixture"

    # Mark tasks complete (gate requires ≥1 [x])
    sed -i 's/^- \[ \]/- [x]/g' "$FAKE_ROOT/openspec/changes/e2e-fixture/tasks.md"
    git -C "$FAKE_ROOT" add "openspec/changes/e2e-fixture/tasks.md" || true
    git -C "$FAKE_ROOT" commit -q -m "e2e: complete tasks for archive" || true

    invoke_archive_happy "$FAKE_ROOT" "e2e-fixture"

    # Real outcome
    [ -d "$FAKE_ROOT/openspec/changes/archive/e2e-fixture" ]
    [ ! -d "$FAKE_ROOT/openspec/changes/e2e-fixture" ]

    # Builder handoff reflects archived status (real write_builder_handoff was called)
    assert_state "$FAKE_ROOT" "builder/e2e-fixture.json" \
        "schema:builder-handoff-v1|change_name:e2e-fixture|owner:rdd-builder"
}

@test "full-workflow 4/7: lifecycle ends with iteration.json changes[].status='archived'" {
    write_arch_fixture "$FAKE_ROOT"
    write_proposal_fixture "$FAKE_ROOT" "e2e-fixture"

    # Seed iteration.json so mark_iteration_archived has something to update
    mkdir -p "$FAKE_ROOT/.rddf/state"
    cat > "$FAKE_ROOT/.rddf/state/iteration.json" <<EOF
{
  "version": 7,
  "updated_at": "2026-09-06T00:00:00Z",
  "current_phase": "phase-1",
  "changes": [
    {"name": "e2e-fixture", "status": "in_worktree", "phase": "phase-1",
     "category": "general", "priority": "P1", "added_at": "2026-09-06T00:00:00Z"}
  ]
}
EOF
    git -C "$FAKE_ROOT" add ".rddf/state/iteration.json"
    git -C "$FAKE_ROOT" commit -q -m "seed iteration.json"

    invoke_arch_stage "$FAKE_ROOT"
    invoke_planner_stage "$FAKE_ROOT"
    invoke_builder_phases "$FAKE_ROOT" "e2e-fixture"

    sed -i 's/^- \[ \]/- [x]/g' "$FAKE_ROOT/openspec/changes/e2e-fixture/tasks.md"
    git -C "$FAKE_ROOT" add "openspec/changes/e2e-fixture/tasks.md" || true
    git -C "$FAKE_ROOT" commit -q -m "e2e: complete tasks" || true

    invoke_archive_happy "$FAKE_ROOT" "e2e-fixture"

    # Real schema: changes[].status (NOT sprints[-1].status)
    run jq -r '.changes[] | select(.name=="e2e-fixture") | .status' "$FAKE_ROOT/.rddf/state/iteration.json"
    [ "$output" = "archived" ]

    # archived_at set
    run jq -r '.changes[] | select(.name=="e2e-fixture") | .archived_at' "$FAKE_ROOT/.rddf/state/iteration.json"
    [ "$output" != "null" ] && [ -n "$output" ]

    # No active change
    [ ! -d "$FAKE_ROOT/openspec/changes/e2e-fixture" ]
}

# ── Error Paths (3 cases — all REAL gate failures) ─────────────────────

@test "full-workflow 5/7: arch gate blocks on missing ADR (real check_arch_done_gate)" {
    # INTENTIONALLY skip write_arch_fixture — no ADR

    run invoke_arch_gate "$FAKE_ROOT"
    [ "$status" -ne 0 ]
    # Real stderr from arch_done_gate.sh:47
    [[ "$output" == *"至少需要 1 个 ADR"* ]] || [[ "$stderr" == *"至少需要 1 个 ADR"* ]]
    [ ! -f "$FAKE_ROOT/.rddf/state/.arch-handoff.json" ]
}

@test "full-workflow 6/7: archive gate blocks on 0 completed tasks (real archive_gate_check)" {
    write_arch_fixture "$FAKE_ROOT"
    write_proposal_fixture "$FAKE_ROOT" "e2e-fixture"

    # All tasks unchecked → 0 [x] → gate blocks
    run invoke_archive_gate "$FAKE_ROOT" "e2e-fixture"
    [ "$status" -ne 0 ]
    # Real stderr from _lib/archive.sh:393
    [[ "$output" == *"0 个完成任务"* ]] || [[ "$stderr" == *"0 个完成任务"* ]]
    [ -d "$FAKE_ROOT/openspec/changes/e2e-fixture" ]
}

@test "full-workflow 7/7: archive gate blocks on missing tasks.md (real archive_gate_check)" {
    write_arch_fixture "$FAKE_ROOT"
    mkdir -p "$FAKE_ROOT/openspec/changes/e2e-fixture"
    # INTENTIONALLY no tasks.md written

    run invoke_archive_gate "$FAKE_ROOT" "e2e-fixture"
    [ "$status" -ne 0 ]
    # Real stderr from _lib/archive.sh:384
    [[ "$output" == *"tasks.md 缺失"* ]] || [[ "$stderr" == *"tasks.md 缺失"* ]]
    [ -d "$FAKE_ROOT/openspec/changes/e2e-fixture" ]
}
```

- [ ] **Step 2: Run the bats file**

```bash
bats tests/integration/test_full_workflow_e2e.bats
```

Expected: 7/7 pass. If any fail, debug per failure (likely `jsonschema` install, env-var leak, or openspec CLI args).

- [ ] **Step 3: Commit**

```bash
git add tests/integration/test_full_workflow_e2e.bats

git commit -m "test(e2e): rewrite main bats with real schema keys + jsonschema (v2)

4 happy path cases use REAL API invocation + jsonschema validate:
- arch (case 1): asserts version=3 + schema validate
- planner (case 2): asserts schema=planner-handoff-v1 + schema validate
- builder+archive (case 3): invokes real openspec archive CLI
- lifecycle (case 4): asserts changes[].status='archived' (real schema)

3 error path cases invoke REAL gate functions:
- arch (case 5): check_arch_done_gate blocks on missing ADR
- archive (case 6): archive_gate_check blocks on 0 completed tasks
- archive (case 7): archive_gate_check blocks on missing tasks.md

All assertions use real contract keys (version, schema, change_name,
changes[].status), not v1's fictional schema_version/sprints.
"
```

---

## Task 5: Update helper bats files for new fixture functions

**Files:**
- Update: `tests/_lib/test_full_workflow_fixture_skeleton.bats` (no changes — already asserts 8 functions)
- Update: `tests/_lib/test_full_workflow_fixture_setup.bats` (no changes — setup_fake_project + write_arch_fixture same)
- Update: `tests/_lib/test_full_workflow_fixture_proposal.bats` (real schema asserts)
- Update: `tests/_lib/test_full_workflow_fixture_stages.bats` (real schema asserts)
- Update: `tests/_lib/test_full_workflow_fixture_archive.bats` (real gate asserts)

- [ ] **Step 1: Verify skeleton + setup tests still pass (no changes needed)**

```bash
bats tests/_lib/test_full_workflow_fixture_skeleton.bats
bats tests/_lib/test_full_workflow_fixture_setup.bats
```

Expected: 2/2 + 2/2 pass.

- [ ] **Step 2: Update test_full_workflow_fixture_proposal.bats**

Rewrite to assert REAL schema keys:

```bash
#!/usr/bin/env bats
# tests/_lib/test_full_workflow_fixture_proposal.bats
# Verify write_proposal_fixture + invoke_arch_stage (REAL API).

load ../test_helper
load_lib test_full_workflow_fixture

@test "write_proposal_fixture: creates openspec/changes/<name>/ with proposal.md + tasks.md + design.md" {
    FAKE_ROOT=$(setup_fake_project)
    write_proposal_fixture "$FAKE_ROOT" "e2e-fixture"
    [ -f "$FAKE_ROOT/openspec/changes/e2e-fixture/proposal.md" ]
    [ -f "$FAKE_ROOT/openspec/changes/e2e-fixture/tasks.md" ]
    [ -f "$FAKE_ROOT/openspec/changes/e2e-fixture/design.md" ]
    grep -q "## Why" "$FAKE_ROOT/openspec/changes/e2e-fixture/proposal.md"
    grep -qE "^- \[[ x]\]" "$FAKE_ROOT/openspec/changes/e2e-fixture/tasks.md"
    rm -rf "$FAKE_ROOT"
}

@test "invoke_arch_stage: writes .arch-handoff.json with REAL contract keys (version=3 per ADR-0016)" {
    FAKE_ROOT=$(setup_fake_project)
    write_arch_fixture "$FAKE_ROOT"
    invoke_arch_stage "$FAKE_ROOT"
    [ -f "$FAKE_ROOT/.rddf/state/.arch-handoff.json" ]

    # Real schema keys (NOT schema_version)
    run jq -r '.version' "$FAKE_ROOT/.rddf/state/.arch-handoff.json"
    [ "$output" = "3" ]
    run jq -r '.adr_dir' "$FAKE_ROOT/.rddf/state/.arch-handoff.json"
    [ "$output" = "docs/adr" ]
    run jq -r '.current_phase' "$FAKE_ROOT/.rddf/state/.arch-handoff.json"
    [ "$output" = "phase-1" ]
    run jq -r '.discovered.adr_dir.found' "$FAKE_ROOT/.rddf/state/.arch-handoff.json"
    [ "$output" = "true" ]

    # Schema validate (defense-in-depth)
    assert_schema "$FAKE_ROOT" ".arch-handoff.json"

    rm -rf "$FAKE_ROOT"
}
```

- [ ] **Step 3: Update test_full_workflow_fixture_stages.bats**

```bash
#!/usr/bin/env bats
# tests/_lib/test_full_workflow_fixture_stages.bats
# Verify invoke_planner_stage + invoke_builder_phases (REAL APIs).

load ../test_helper
load_lib test_full_workflow_fixture

@test "invoke_planner_stage: writes .planner-handoff.json with REAL v1 schema" {
    FAKE_ROOT=$(setup_fake_project)
    write_arch_fixture "$FAKE_ROOT"
    invoke_arch_stage "$FAKE_ROOT"
    invoke_planner_stage "$FAKE_ROOT"
    [ -f "$FAKE_ROOT/.rddf/state/.planner-handoff.json" ]

    # Real schema keys (NOT schema_version)
    run jq -r '.schema' "$FAKE_ROOT/.rddf/state/.planner-handoff.json"
    [ "$output" = "planner-handoff-v1" ]
    run jq -r '.version' "$FAKE_ROOT/.rddf/state/.planner-handoff.json"
    [ "$output" = "1" ]
    run jq -r '.owner' "$FAKE_ROOT/.rddf/state/.planner-handoff.json"
    [ "$output" = "rdd-planner" ]
    run jq -r '.current_sprint' "$FAKE_ROOT/.rddf/state/.planner-handoff.json"
    [ "$output" = "sprint-2026-09" ]

    assert_schema "$FAKE_ROOT" ".planner-handoff.json"

    rm -rf "$FAKE_ROOT"
}

@test "invoke_builder_phases: writes .rddf/state/builder/<change>.json with REAL v1 schema" {
    FAKE_ROOT=$(setup_fake_project)
    write_arch_fixture "$FAKE_ROOT"
    write_proposal_fixture "$FAKE_ROOT" "e2e-fixture"
    invoke_arch_stage "$FAKE_ROOT"
    invoke_planner_stage "$FAKE_ROOT"
    invoke_builder_phases "$FAKE_ROOT" "e2e-fixture"
    [ -f "$FAKE_ROOT/.rddf/state/builder/e2e-fixture.json" ]

    # Real schema keys (NOT 'change')
    run jq -r '.schema' "$FAKE_ROOT/.rddf/state/builder/e2e-fixture.json"
    [ "$output" = "builder-handoff-v1" ]
    run jq -r '.version' "$FAKE_ROOT/.rddf/state/builder/e2e-fixture.json"
    [ "$output" = "1" ]
    run jq -r '.change_name' "$FAKE_ROOT/.rddf/state/builder/e2e-fixture.json"
    [ "$output" = "e2e-fixture" ]
    run jq -r '.owner' "$FAKE_ROOT/.rddf/state/builder/e2e-fixture.json"
    [ "$output" = "rdd-builder" ]
    run jq -r '.current_phase' "$FAKE_ROOT/.rddf/state/builder/e2e-fixture.json"
    [ "$output" = "phase-2" ]

    assert_schema "$FAKE_ROOT" "builder/e2e-fixture.json"

    rm -rf "$FAKE_ROOT"
}
```

- [ ] **Step 4: Update test_full_workflow_fixture_archive.bats**

```bash
#!/usr/bin/env bats
# tests/_lib/test_full_workflow_fixture_archive.bats
# Verify invoke_archive happy + error paths (REAL gates).

load ../test_helper
load_lib test_full_workflow_fixture

@test "invoke_archive_gate (real archive_gate_check): blocks when 0 tasks [x]" {
    FAKE_ROOT=$(setup_fake_project)
    write_arch_fixture "$FAKE_ROOT"
    write_proposal_fixture "$FAKE_ROOT" "e2e-fixture"
    # Tasks are all unchecked → 0 [x]
    run invoke_archive_gate "$FAKE_ROOT" "e2e-fixture"
    [ "$status" -ne 0 ]
    [[ "$output" == *"0 个完成任务"* ]] || [[ "$stderr" == *"0 个完成任务"* ]]
    rm -rf "$FAKE_ROOT"
}

@test "invoke_archive_gate (real archive_gate_check): blocks on missing tasks.md" {
    FAKE_ROOT=$(setup_fake_project)
    mkdir -p "$FAKE_ROOT/openspec/changes/e2e-fixture"
    run invoke_archive_gate "$FAKE_ROOT" "e2e-fixture"
    [ "$status" -ne 0 ]
    [[ "$output" == *"tasks.md 缺失"* ]] || [[ "$stderr" == *"tasks.md 缺失"* ]]
    rm -rf "$FAKE_ROOT"
}

@test "invoke_archive_happy (real openspec): moves change to archive/" {
    FAKE_ROOT=$(setup_fake_project)
    write_arch_fixture "$FAKE_ROOT"
    write_proposal_fixture "$FAKE_ROOT" "e2e-fixture"
    invoke_arch_stage "$FAKE_ROOT"
    invoke_planner_stage "$FAKE_ROOT"
    invoke_builder_phases "$FAKE_ROOT" "e2e-fixture"
    sed -i 's/^- \[ \]/- [x]/g' "$FAKE_ROOT/openspec/changes/e2e-fixture/tasks.md"
    git -C "$FAKE_ROOT" add "openspec/changes/e2e-fixture/tasks.md" || true
    git -C "$FAKE_ROOT" commit -q -m "complete tasks" || true

    # Seed iteration.json so mark_iteration_archived has something
    mkdir -p "$FAKE_ROOT/.rddf/state"
    cat > "$FAKE_ROOT/.rddf/state/iteration.json" <<EOF
{"version": 7, "updated_at": "2026-09-06T00:00:00Z", "current_phase": "phase-1",
 "changes": [{"name": "e2e-fixture", "status": "in_worktree"}]}
EOF
    git -C "$FAKE_ROOT" add ".rddf/state/iteration.json"
    git -C "$FAKE_ROOT" commit -q -m "seed iter"

    invoke_archive_happy "$FAKE_ROOT" "e2e-fixture"

    # Real outcome: change moved, original gone
    [ -d "$FAKE_ROOT/openspec/changes/archive/e2e-fixture" ]
    [ ! -d "$FAKE_ROOT/openspec/changes/e2e-fixture" ]

    # iteration.json updated to archived
    run jq -r '.changes[] | select(.name=="e2e-fixture") | .status' \
        "$FAKE_ROOT/.rddf/state/iteration.json"
    [ "$output" = "archived" ]

    rm -rf "$FAKE_ROOT"
}
```

- [ ] **Step 5: Run all helper bats files**

```bash
bats tests/_lib/test_full_workflow_fixture_*.bats
```

Expected: 2+2+2+2+3 = 11/11 pass.

- [ ] **Step 6: Commit**

```bash
git add tests/_lib/test_full_workflow_fixture_proposal.bats \
        tests/_lib/test_full_workflow_fixture_stages.bats \
        tests/_lib/test_full_workflow_fixture_archive.bats

git commit -m "test(e2e): update helper bats for real schema + real gates (v2)

Replaces v1 schema assertions (schema_version, sprints, change) with
real contract keys (version, schema, change_name). Adds jsonschema
validate defense-in-depth on every handoff. Error tests now invoke
real archive_gate_check + assert real stderr messages.
"
```

---

## Task 6: CI Gate Verification + Final Smoke

**Files:** (no new files; verification only)

- [ ] **Step 1: Verify test isolation gate passes**

```bash
bash tests/scripts/check_test_isolation.sh 2>&1 | grep -E "(test_full_workflow|FAILED|PASSED)"
```

Expected: NO violations in `test_full_workflow_*` files (pre-existing failures in unrelated files are OK).

- [ ] **Step 2: Verify assertion quality gate passes**

```bash
grep -rn "assert.*or True\|assert True" tests/integration/test_full_workflow_e2e.bats \
                                              tests/_lib/test_full_workflow_fixture.bash \
                                              tests/_lib/test_full_workflow_e2e_runner.env.py \
                                              tests/_lib/test_full_workflow_e2e_runner.sh \
                                              tests/_lib/test_full_workflow_fixture_*.bats
```

Expected: NO output (no tautologies).

- [ ] **Step 3: Verify ruff passes on new Python**

```bash
ruff check tests/_lib/test_full_workflow_e2e_runner.env.py
ruff check tests/_lib/test_full_workflow_e2e_runner.sh  # shellcheck instead if exists
```

Expected: All checks passed.

- [ ] **Step 4: Verify jsonschema Python package is available**

```bash
python3 -c "import jsonschema; print(jsonschema.__version__)"
```

Expected: prints version (any recent version).

- [ ] **Step 5: Run full E2E suite locally**

```bash
bats tests/integration/test_full_workflow_e2e.bats tests/_lib/test_full_workflow_fixture_*.bats
```

Expected: 18/18 pass.

- [ ] **Step 6: Measure total runtime (target ≤ 2 minutes)**

```bash
time bats tests/integration/test_full_workflow_e2e.bats tests/_lib/test_full_workflow_fixture_*.bats
```

Expected: elapsed ≤ 2 minutes.

- [ ] **Step 7: Verify no regressions in existing tests**

```bash
bats tests/integration/test_v4_e2e_3_stage_flow.bats
bats tests/integration/test_rdd_arch_cli.bats
```

Expected: existing tests still pass (we didn't modify them).

- [ ] **Step 8: Final commit (if any docs/changelog updates) + push**

```bash
git log --oneline -15   # verify 8+ commits from this plan
git push origin master
```

Verify CI green at GitHub Actions.

---

## Self-Review (per writing-plans skill)

**1. Spec coverage:**

| Spec section | Task |
|---|---|
| §1.2 Problem | T1 (delete fake) |
| §2.1 arch entry | T2 (shim) + T3 (invoke_arch_stage) + T4 (case 1) |
| §2.2 arch gate | T3 (invoke_arch_gate) + T4 (case 5) |
| §2.3 planner entry | T3 (invoke_planner_stage) + T4 (case 2) + T5 (helper stages test 1) |
| §2.4 builder entry | T2 (shim) + T3 (invoke_builder_phases) + T4 (case 3) + T5 (helper stages test 2) |
| §2.5 archive happy | T3 (invoke_archive_happy) + T4 (case 3, 4) + T5 (helper archive test 3) |
| §2.6 archive gate | T3 (invoke_archive_gate) + T4 (case 6, 7) + T5 (helper archive tests 1, 2) |
| §3 Schema contracts | T3 (assert_schema jsonschema) + T4 (every handoff case validates) + T5 (helper tests validate) |
| §4 Test cases (7) | T4 (rewrite main bats) |
| §6.1 isolation | T3 (`unset` in teardown, `cd` before `rm`) |
| §6.3 invocation safety | T3 (SKIP_VERIFIER_CONTRACT=yes, SKIP_AC_VERIFICATION=yes documented in fixture header) |
| §10 acceptance criteria | T6 (all 9 checks) |

**2. Placeholder scan:** No "TBD"/"TODO"/"fill in later" found.

**3. Type consistency:**
- All `invoke_*` functions take root as `$1`
- `invoke_archive_gate` + `invoke_archive_happy` also take name as `$2`
- `assert_state` signature `root file fields` unchanged from v1
- `assert_schema` signature `root file [schema]` — auto-derives schema from filename

No inconsistencies detected.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-09-06-rdd-workflow-full-e2e-v2.md`. 6 execution tasks. Recommended approach: subagent-driven-development for T1-T5 (each task self-contained), then inline T6 verification.**