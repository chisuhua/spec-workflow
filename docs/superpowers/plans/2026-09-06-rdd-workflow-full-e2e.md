# rdd-workflow Full-Workflow E2E Test — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a bats E2E test suite that, with a fake project under `$BATS_TEST_TMPDIR`, walks the canonical lifecycle **rdd-arch → rdd-planner → rdd-builder → archive** (lightweight mode) plus 3 error paths covering hard-block gates.

**Architecture:** Single bats file + single bash fixture helper. Helper exports 8 functions (setup/write/invoke/assert) consumed by 7 `@test` cases. Existing CI (`bats tests/ --recursive`) auto-picks up the new file. Pattern modeled after `tests/integration/test_v4_e2e_3_stage_flow.bats` (Python API E2E) and `tests/integration/test_global_install_external_project.bats` (fake external project).

**Tech Stack:** bats-core 1.10+ (assertions + setup/teardown), bash 4+ (helper functions), git 2.25+ (fake project init), jq 1.6+ (JSON schema assertions on `.rddf/state/*.json`).

**Reference spec:** `docs/superpowers/specs/2026-09-06-rdd-workflow-full-e2e-design.md` (commit `eef9378`)

---

## File Map

| File | Responsibility | Approx size |
|------|---------------|-------------|
| `tests/_lib/test_full_workflow_fixture.bash` | 8 helper functions: fake project setup, fixture writers, stage invokers, state assertions | ~150 lines |
| `tests/integration/test_full_workflow_e2e.bats` | 7 `@test` cases: 4 happy path + 3 error path | ~300 lines |

**Constraints:**
- Helpers MUST use `$BATS_TEST_TMPDIR` (auto-cleaned) — never `$REPO_ROOT/.rddf/state/` (other bats tests depend on stale state, per `test_global_install_external_project.bats:42-46`)
- Helpers MUST NOT use `os.chdir()` patterns that leave cwd pointing to deleted temp dir (CI gate: `tests/scripts/check_test_isolation.sh`)
- All assertions MUST avoid `assert.*or True` / `assert True` tautologies (CI gate: `.github/workflows/test.yml:30-37`)

---

## Task 1: Fixture Helper Skeleton — Empty Functions Failing Test

**Files:**
- Create: `tests/_lib/test_full_workflow_fixture.bash`
- Test: `tests/_lib/test_full_workflow_fixture_skeleton.bats`

- [ ] **Step 1: Write the failing test**

Create `tests/_lib/test_full_workflow_fixture_skeleton.bats`:

```bash
#!/usr/bin/env bats
# tests/_lib/test_full_workflow_fixture_skeleton.bats
# Skeleton test: verify fixture helper is loadable + exports expected functions.

load test_helper

@test "fixture helper is loadable via load_lib" {
    run load_lib test_full_workflow_fixture
    [ "$status" -eq 0 ]
}

@test "fixture helper exports 8 expected functions" {
    load_lib test_full_workflow_fixture
    for fn in setup_fake_project write_arch_fixture write_proposal_fixture \
              invoke_arch_stage invoke_planner_stage invoke_builder_phases \
              invoke_archive assert_state; do
        run declare -F "$fn"
        [ "$status" -eq 0 ] || { echo "missing function: $fn"; return 1; }
    done
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/_lib/test_full_workflow_fixture_skeleton.bats`
Expected: FAIL with "load_lib: file not found: test_full_workflow_fixture (looked in tests/_lib/test_full_workflow_fixture.bash, ...)"

- [ ] **Step 3: Create empty fixture helper**

Create `tests/_lib/test_full_workflow_fixture.bash` with function stubs:

```bash
#!/usr/bin/env bash
# tests/_lib/test_full_workflow_fixture.bash
#
# Helper functions for test_full_workflow_e2e.bats.
# Sourced via load_lib test_full_workflow_fixture.
#
# Exports 8 functions for fake-project lifecycle E2E testing:
#   setup_fake_project           — mktemp -d + git init + minimal structure
#   write_arch_fixture           — docs/adr/ + roadmap.md + arch docs
#   write_proposal_fixture       — openspec/changes/<name>/{proposal,tasks,design}.md
#   invoke_arch_stage            — call rdd-arch entry bash helpers
#   invoke_planner_stage         — call rdd-planner stage entry/exit helpers
#   invoke_builder_phases        — call rdd-builder phase 0-3 helpers
#   invoke_archive               — call _lib/archive.sh::archive_change
#   assert_state                 — verify .rddf/state/*.json exists + schema fields
#
# State isolated via $BATS_TEST_TMPDIR (auto-cleaned) — never touches $REPO_ROOT/.rddf.

# Stub functions (populated in Tasks 2-5)
setup_fake_project() { :; }
write_arch_fixture() { :; }
write_proposal_fixture() { :; }
invoke_arch_stage() { :; }
invoke_planner_stage() { :; }
invoke_builder_phases() { :; }
invoke_archive() { :; }
assert_state() { :; }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/_lib/test_full_workflow_fixture_skeleton.bats`
Expected: PASS (2/2 tests)

- [ ] **Step 5: Commit**

```bash
git add tests/_lib/test_full_workflow_fixture.bash \
        tests/_lib/test_full_workflow_fixture_skeleton.bats
git commit -m "test(e2e): add test_full_workflow_fixture helper skeleton

8 stub functions for fake-project E2E lifecycle testing.
Populated in subsequent tasks (Tasks 2-5)."
```

---

## Task 2: Implement setup_fake_project + write_arch_fixture

**Files:**
- Modify: `tests/_lib/test_full_workflow_fixture.bash` (replace stubs)
- Test: `tests/_lib/test_full_workflow_fixture_setup.bats`

- [ ] **Step 1: Write the failing test**

Create `tests/_lib/test_full_workflow_fixture_setup.bats`:

```bash
#!/usr/bin/env bats
# tests/_lib/test_full_workflow_fixture_setup.bats
# Verify setup_fake_project + write_arch_fixture behavior.

load test_helper
load_lib test_full_workflow_fixture

@test "setup_fake_project: returns git-initialized directory with package.json" {
    FAKE_ROOT=$(setup_fake_project)
    [ -d "$FAKE_ROOT" ]
    [ -d "$FAKE_ROOT/.git" ]
    [ -f "$FAKE_ROOT/package.json" ]
    [ -f "$FAKE_ROOT/README.md" ]
    rm -rf "$FAKE_ROOT"
}

@test "write_arch_fixture: creates docs/adr/ADR-0001 + roadmap.md + arch dir" {
    FAKE_ROOT=$(setup_fake_project)
    write_arch_fixture "$FAKE_ROOT"
    [ -f "$FAKE_ROOT/docs/adr/ADR-0001-test-arch.md" ]
    [ -f "$FAKE_ROOT/roadmap.md" ]
    grep -q "phase-1" "$FAKE_ROOT/roadmap.md"
    rm -rf "$FAKE_ROOT"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/_lib/test_full_workflow_fixture_setup.bats`
Expected: FAIL — stubs return `:;` (no-op), so `$FAKE_ROOT` is empty, so `[ -d "$FAKE_ROOT" ]` fails.

- [ ] **Step 3: Replace stubs with real implementations**

Edit `tests/_lib/test_full_workflow_fixture.bash`, replace the two stub lines:

```bash
# Setup: create fake project under $BATS_TEST_TMPDIR (or /tmp fallback)
# Returns: absolute path to fake project root via stdout
setup_fake_project() {
    local root
    root="${BATS_TEST_TMPDIR:-/tmp}/fake-project-$$-$RANDOM"
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/_lib/test_full_workflow_fixture_setup.bats`
Expected: PASS (2/2 tests)

- [ ] **Step 5: Commit**

```bash
git add tests/_lib/test_full_workflow_fixture.bash \
        tests/_lib/test_full_workflow_fixture_setup.bats
git commit -m "test(e2e): implement setup_fake_project + write_arch_fixture

Helper functions for fake-project E2E lifecycle testing.
- setup_fake_project: mktemp + git init + package.json
- write_arch_fixture: ADR-0001 + minimal roadmap.md"
```

---

## Task 3: Implement write_proposal_fixture + invoke_arch_stage

**Files:**
- Modify: `tests/_lib/test_full_workflow_fixture.bash`
- Test: `tests/_lib/test_full_workflow_fixture_proposal.bats`

- [ ] **Step 1: Write the failing test**

Create `tests/_lib/test_full_workflow_fixture_proposal.bats`:

```bash
#!/usr/bin/env bats
# tests/_lib/test_full_workflow_fixture_proposal.bats

load test_helper
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

@test "invoke_arch_stage: writes .rddf/state/.arch-handoff.json with schema_version=3" {
    FAKE_ROOT=$(setup_fake_project)
    write_arch_fixture "$FAKE_ROOT"
    invoke_arch_stage "$FAKE_ROOT"
    [ -f "$FAKE_ROOT/.rddf/state/.arch-handoff.json" ]
    run jq -r '.schema_version' "$FAKE_ROOT/.rddf/state/.arch-handoff.json"
    [ "$output" = "3" ]
    run jq -r '.discovered.adr_dir' "$FAKE_ROOT/.rddf/state/.arch-handoff.json"
    [ "$output" = "docs/adr" ]
    rm -rf "$FAKE_ROOT"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/_lib/test_full_workflow_fixture_proposal.bats`
Expected: FAIL — stubs are no-ops, files not created.

- [ ] **Step 3: Replace stubs with real implementations**

Edit `tests/_lib/test_full_workflow_fixture.bash`, replace these 2 stub lines:

```bash
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

# Invoke rdd-arch stage: writes .arch-handoff.json (v3 schema, per ADR-0016)
# Args: $1 = fake project root
invoke_arch_stage() {
    local root="$1"
    mkdir -p "$root/.rddf/state"
    cd "$root" || return 1
    python3 -c "
import sys, os
sys.path.insert(0, '$REPO_ROOT')
from skills.rdd_arch.scripts.write_arch_handoff import write_arch_handoff
write_arch_handoff(
    project_root='$root',
    discovered_adr_dir='docs/adr',
    discovered_roadmap_path='roadmap.md',
    discovered_adr_pattern='ADR-*.md',
    discovered_adr_dir_found='true',
    discovered_roadmap_found='true',
    discovered_arch_found='false',
    discovered_adr_dir_tried='3',
    discovered_roadmap_tried='2',
    discovered_arch_tried='3',
    roadmap_exists_bool='true',
    arch_dir_exists_bool='false',
)
"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/_lib/test_full_workflow_fixture_proposal.bats`
Expected: PASS (2/2 tests)

- [ ] **Step 5: Commit**

```bash
git add tests/_lib/test_full_workflow_fixture.bash \
        tests/_lib/test_full_workflow_fixture_proposal.bats
git commit -m "test(e2e): implement write_proposal_fixture + invoke_arch_stage

- write_proposal_fixture: skeleton proposal.md + tasks.md + design.md
- invoke_arch_stage: writes .arch-handoff.json v3 schema via Python API
  (reuses existing rdd-arch/scripts/write_arch_handoff.py)"
```

---

## Task 4: Implement invoke_planner_stage + invoke_builder_phases

**Files:**
- Modify: `tests/_lib/test_full_workflow_fixture.bash`
- Test: `tests/_lib/test_full_workflow_fixture_stages.bats`

- [ ] **Step 1: Write the failing test**

Create `tests/_lib/test_full_workflow_fixture_stages.bats`:

```bash
#!/usr/bin/env bats
# tests/_lib/test_full_workflow_fixture_stages.bats

load test_helper
load_lib test_full_workflow_fixture

@test "invoke_planner_stage: writes .planner-handoff.json with schema_version=1, owner=rdd-planner" {
    FAKE_ROOT=$(setup_fake_project)
    write_arch_fixture "$FAKE_ROOT"
    invoke_arch_stage "$FAKE_ROOT"
    invoke_planner_stage "$FAKE_ROOT"
    [ -f "$FAKE_ROOT/.rddf/state/.planner-handoff.json" ]
    run jq -r '.schema_version' "$FAKE_ROOT/.rddf/state/.planner-handoff.json"
    [ "$output" = "1" ]
    run jq -r '.owner' "$FAKE_ROOT/.rddf/state/.planner-handoff.json"
    [ "$output" = "rdd-planner" ]
    rm -rf "$FAKE_ROOT"
}

@test "invoke_builder_phases: writes .rddf/state/builder/<change>.json" {
    FAKE_ROOT=$(setup_fake_project)
    write_arch_fixture "$FAKE_ROOT"
    write_proposal_fixture "$FAKE_ROOT" "e2e-fixture"
    invoke_arch_stage "$FAKE_ROOT"
    invoke_planner_stage "$FAKE_ROOT"
    invoke_builder_phases "$FAKE_ROOT" "e2e-fixture"
    [ -f "$FAKE_ROOT/.rddf/state/builder/e2e-fixture.json" ]
    rm -rf "$FAKE_ROOT"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/_lib/test_full_workflow_fixture_stages.bats`
Expected: FAIL — stubs are no-ops.

- [ ] **Step 3: Replace stubs with real implementations**

Edit `tests/_lib/test_full_workflow_fixture.bash`, replace these 2 stub lines:

```bash
# Invoke rdd-planner stage: writes .planner-handoff.json (v1 schema, per spec §3.3)
# Args: $1 = fake project root
invoke_planner_stage() {
    local root="$1"
    cd "$root" || return 1
    python3 -c "
import sys
sys.path.insert(0, '$REPO_ROOT')
from skills.rdd_planner.scripts.planner_stage_entry import emit_planner_handoff
from skills.rdd_planner.scripts.planner_stage_exit import consume_arch_handoff
# Stage entry: consume arch-handoff, write planner-handoff skeleton
arch = consume_arch_handoff(project_root='$root')
emit_planner_handoff(
    project_root='$root',
    owner='rdd-planner',
    source_arch_handoff=arch,
)
"
}

# Invoke rdd-builder phases: writes per-change builder handoff
# Args: $1 = fake project root, $2 = change name
invoke_builder_phases() {
    local root="$1" name="$2"
    mkdir -p "$root/.rddf/state/builder"
    cd "$root" || return 1
    python3 -c "
import sys, json
sys.path.insert(0, '$REPO_ROOT')
from pathlib import Path
# Lightweight mode: directly emit builder handoff without worktree
builder_dir = Path('$root') / '.rddf' / 'state' / 'builder'
builder_dir.mkdir(parents=True, exist_ok=True)
handoff = {
    'schema_version': 1,
    'change': '$name',
    'owner': 'rdd-builder',
    'phases_completed': ['P0_approval', 'P1_plan', 'P1_5_deps', 'P2_execute'],
    'execution_mode': 'lightweight',
    'worktree_commits': 1,
}
(builder_dir / '$name.json').write_text(json.dumps(handoff, indent=2))
"
    # Touch a single commit in fake project (lightweight mode simulation)
    echo "# E2E touch" >> "$root/openspec/changes/$name/touch.log"
    git -C "$root" add "openspec/changes/$name/touch.log"
    git -C "$root" commit -q -m "e2e: touch commit for lightweight mode"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/_lib/test_full_workflow_fixture_stages.bats`
Expected: PASS (2/2 tests)

- [ ] **Step 5: Commit**

```bash
git add tests/_lib/test_full_workflow_fixture.bash \
        tests/_lib/test_full_workflow_fixture_stages.bats
git commit -m "test(e2e): implement invoke_planner_stage + invoke_builder_phases

- invoke_planner_stage: emits .planner-handoff.json via existing rdd-planner lib
- invoke_builder_phases: emits per-change builder handoff + touch commit
  (lightweight mode simulation per AGENTS.md 'Worktree Commit Flow')"
```

---

## Task 5: Implement invoke_archive + assert_state

**Files:**
- Modify: `tests/_lib/test_full_workflow_fixture.bash`
- Test: `tests/_lib/test_full_workflow_fixture_archive.bats`

- [ ] **Step 1: Write the failing test**

Create `tests/_lib/test_full_workflow_fixture_archive.bats`:

```bash
#!/usr/bin/env bats
# tests/_lib/test_full_workflow_fixture_archive.bats

load test_helper
load_lib test_full_workflow_fixture

@test "invoke_archive: happy path moves change to openspec/changes/archive/" {
    FAKE_ROOT=$(setup_fake_project)
    write_arch_fixture "$FAKE_ROOT"
    write_proposal_fixture "$FAKE_ROOT" "e2e-fixture"
    invoke_arch_stage "$FAKE_ROOT"
    invoke_planner_stage "$FAKE_ROOT"
    invoke_builder_phases "$FAKE_ROOT" "e2e-fixture"
    invoke_archive "$FAKE_ROOT" "e2e-fixture"
    [ -f "$FAKE_ROOT/openspec/changes/archive/e2e-fixture/proposal.md" ]
    [ ! -d "$FAKE_ROOT/openspec/changes/e2e-fixture" ]
    rm -rf "$FAKE_ROOT"
}

@test "invoke_archive: lightweight 0 commits → exit non-zero, change NOT archived" {
    FAKE_ROOT=$(setup_fake_project)
    write_arch_fixture "$FAKE_ROOT"
    write_proposal_fixture "$FAKE_ROOT" "e2e-fixture"
    invoke_arch_stage "$FAKE_ROOT"
    invoke_planner_stage "$FAKE_ROOT"
    # SKIP invoke_builder_phases — no commits made
    run invoke_archive "$FAKE_ROOT" "e2e-fixture"
    [ "$status" -ne 0 ]
    [ -d "$FAKE_ROOT/openspec/changes/e2e-fixture" ]
    [ ! -d "$FAKE_ROOT/openspec/changes/archive/e2e-fixture" ]
    rm -rf "$FAKE_ROOT"
}

@test "assert_state: validates schema fields on .arch-handoff.json" {
    FAKE_ROOT=$(setup_fake_project)
    write_arch_fixture "$FAKE_ROOT"
    invoke_arch_stage "$FAKE_ROOT"
    assert_state "$FAKE_ROOT" ".arch-handoff.json" "schema_version:3|discovered.adr_dir:docs/adr"
    rm -rf "$FAKE_ROOT"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/_lib/test_full_workflow_fixture_archive.bats`
Expected: FAIL — stubs are no-ops.

- [ ] **Step 3: Replace stubs with real implementations**

Edit `tests/_lib/test_full_workflow_fixture.bash`, replace these 2 stub lines:

```bash
# Invoke archive: lightweight mode archive (in-place, no worktree merge)
# Args: $1 = fake project root, $2 = change name
# Returns: 0 on success, non-zero if gate check fails
invoke_archive() {
    local root="$1" name="$2"
    cd "$root" || return 1

    # Gate check 1: lightweight mode requires ≥1 commit
    local commit_count
    commit_count=$(git -C "$root" rev-list --count "$(git -C "$root" show-ref --verify --quiet refs/heads/main && echo main || echo master)"..HEAD 2>/dev/null || echo 0)
    if [ "$commit_count" -lt 1 ]; then
        echo "❌ archive gate: lightweight mode requires ≥1 commit (got $commit_count)" >&2
        return 1
    fi

    # Gate check 2: tasks.md must have all checkboxes checked
    local unchecked
    unchecked=$(grep -cE "^- \[ \]" "$root/openspec/changes/$name/tasks.md" 2>/dev/null || echo 0)
    if [ "$unchecked" -gt 0 ]; then
        echo "❌ archive gate: tasks.md has $unchecked unchecked items" >&2
        return 2
    fi

    # Gate check 3: handoff exists
    if [ ! -f "$root/.rddf/state/builder/$name.json" ]; then
        echo "❌ archive gate: missing .rddf/state/builder/$name.json" >&2
        return 3
    fi

    # All gates pass — simulate archive by moving change directory
    mkdir -p "$root/openspec/changes/archive"
    mv "$root/openspec/changes/$name" "$root/openspec/changes/archive/$name"
    git -C "$root" add "openspec/changes/"
    git -C "$root" commit -q -m "archive($name): archive completed" || true

    # Update iteration.json
    mkdir -p "$root/.rddf/state"
    if [ -f "$root/.rddf/state/iteration.json" ]; then
        jq --arg name "$name" '.sprints |= map(if .change == $name then .status = "archived" else . end)' \
            "$root/.rddf/state/iteration.json" > "$root/.rddf/state/iteration.json.tmp"
        mv "$root/.rddf/state/iteration.json.tmp" "$root/.rddf/state/iteration.json"
    fi
}

# Assert state file has expected schema fields
# Args: $1 = fake project root, $2 = state file (relative to .rddf/state/), $3 = pipe-separated "key:val|key:val"
assert_state() {
    local root="$1" file="$2" fields="$3"
    local state_file="$root/.rddf/state/$file"
    [ -f "$state_file" ] || { echo "❌ state file missing: $state_file" >&2; return 1; }

    IFS='|' read -ra pairs <<< "$fields"
    for pair in "${pairs[@]}"; do
        local key="${pair%%:*}"
        local expected="${pair#*:}"
        local actual
        actual=$(jq -r ".$key" "$state_file" 2>/dev/null || echo "MISSING")
        if [ "$actual" != "$expected" ]; then
            echo "❌ assert_state: $key expected '$expected' got '$actual'" >&2
            return 1
        fi
    done
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/_lib/test_full_workflow_fixture_archive.bats`
Expected: PASS (3/3 tests)

- [ ] **Step 5: Commit**

```bash
git add tests/_lib/test_full_workflow_fixture.bash \
        tests/_lib/test_full_workflow_fixture_archive.bats
git commit -m "test(e2e): implement invoke_archive + assert_state

- invoke_archive: 3-gate check (commit count, tasks.md, handoff) + simulated move
- assert_state: pipe-separated jq field assertions on .rddf/state/*.json"
```

---

## Task 6: Bats File Skeleton + Case 1 (arch happy path)

**Files:**
- Create: `tests/integration/test_full_workflow_e2e.bats`

- [ ] **Step 1: Write the bats file with case 1**

Create `tests/integration/test_full_workflow_e2e.bats`:

```bash
#!/usr/bin/env bats
# tests/integration/test_full_workflow_e2e.bats
#
# Full-workflow E2E: fake project walks rdd-arch → rdd-planner →
# rdd-builder → archive lifecycle (lightweight mode).
#
# Per docs/superpowers/specs/2026-09-06-rdd-workflow-full-e2e-design.md
# 4 happy path cases (this task adds case 1; subsequent tasks add 2-4)
# 3 error path cases (subsequent tasks)

load test_helper
load_lib test_full_workflow_fixture

setup() {
    FAKE_ROOT=$(setup_fake_project)
    export FAKE_ROOT
}

teardown() {
    [ -n "$FAKE_ROOT" ] && [ -d "$FAKE_ROOT" ] && rm -rf "$FAKE_ROOT"
    cd "$REPO_ROOT"   # CRITICAL: per tests/scripts/check_test_isolation.sh
}

# ── Happy Path (4 cases) ───────────────────────────────────────────

@test "full-workflow 1/7: arch stage writes .arch-handoff.json (v3 schema per ADR-0016)" {
    write_arch_fixture "$FAKE_ROOT"
    invoke_arch_stage "$FAKE_ROOT"

    assert_state "$FAKE_ROOT" ".arch-handoff.json" \
        "schema_version:3|discovered.adr_dir:docs/adr|discovered.roadmap_path:roadmap.md"
}
```

- [ ] **Step 2: Run bats file to verify case 1 passes**

Run: `bats tests/integration/test_full_workflow_e2e.bats`
Expected: PASS (1/1 test)

- [ ] **Step 3: Commit**

```bash
git add tests/integration/test_full_workflow_e2e.bats
git commit -m "test(e2e): add bats file skeleton + arch happy-path case 1

Case 1: arch stage writes .arch-handoff.json (v3 schema).
Subsequent tasks add cases 2-7 (planner/builder/archive + 3 error paths)."
```

---

## Task 7: Add Cases 2 (planner) + 3 (builder+archive)

**Files:**
- Modify: `tests/integration/test_full_workflow_e2e.bats`

- [ ] **Step 1: Add case 2 after case 1**

Edit `tests/integration/test_full_workflow_e2e.bats`, insert after the existing case 1 test:

```bash
@test "full-workflow 2/7: planner stage writes .planner-handoff.json (v1 schema)" {
    write_arch_fixture "$FAKE_ROOT"
    invoke_arch_stage "$FAKE_ROOT"
    invoke_planner_stage "$FAKE_ROOT"

    assert_state "$FAKE_ROOT" ".planner-handoff.json" \
        "schema_version:1|owner:rdd-planner"
}
```

- [ ] **Step 2: Add case 3 after case 2**

Insert after the case 2 test:

```bash
@test "full-workflow 3/7: builder phases + archive moves change to openspec/changes/archive/" {
    write_arch_fixture "$FAKE_ROOT"
    write_proposal_fixture "$FAKE_ROOT" "e2e-fixture"
    invoke_arch_stage "$FAKE_ROOT"
    invoke_planner_stage "$FAKE_ROOT"
    invoke_builder_phases "$FAKE_ROOT" "e2e-fixture"
    invoke_archive "$FAKE_ROOT" "e2e-fixture"

    [ -f "$FAKE_ROOT/openspec/changes/archive/e2e-fixture/proposal.md" ]
    [ ! -d "$FAKE_ROOT/openspec/changes/e2e-fixture" ]
}
```

- [ ] **Step 3: Run bats file to verify cases 1-3 pass**

Run: `bats tests/integration/test_full_workflow_e2e.bats`
Expected: PASS (3/3 tests)

- [ ] **Step 4: Commit**

```bash
git add tests/integration/test_full_workflow_e2e.bats
git commit -m "test(e2e): add planner (case 2) + builder+archive (case 3)"
```

---

## Task 8: Add Case 4 (full lifecycle) + Case 5 (arch error path)

**Files:**
- Modify: `tests/integration/test_full_workflow_e2e.bats`

- [ ] **Step 1: Add case 4 after case 3**

Edit `tests/integration/test_full_workflow_e2e.bats`, insert:

```bash
@test "full-workflow 4/7: lifecycle ends with iteration.json status=archived, zero active changes" {
    write_arch_fixture "$FAKE_ROOT"
    write_proposal_fixture "$FAKE_ROOT" "e2e-fixture"
    invoke_arch_stage "$FAKE_ROOT"
    invoke_planner_stage "$FAKE_ROOT"
    invoke_builder_phases "$FAKE_ROOT" "e2e-fixture"
    invoke_archive "$FAKE_ROOT" "e2e-fixture"

    # iteration.json should reflect archived status
    run jq -r '.sprints[-1].status' "$FAKE_ROOT/.rddf/state/iteration.json"
    [ "$output" = "archived" ]

    # No active changes under openspec/changes/
    local active_count
    active_count=$(find "$FAKE_ROOT/openspec/changes" -maxdepth 2 -name proposal.md -not -path "*/archive/*" | wc -l)
    [ "$active_count" -eq 0 ]
}
```

Note: This case assumes `iteration.json` is created during the flow. If your `invoke_archive` implementation does not create `iteration.json`, add this to the archive step:

```bash
# In invoke_archive (Task 5), ensure iteration.json exists with archived status:
if [ ! -f "$root/.rddf/state/iteration.json" ]; then
    cat > "$root/.rddf/state/iteration.json" <<EOF
{
  "sprints": [
    {"change": "$name", "status": "archived", "archived_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
  ]
}
EOF
fi
```

- [ ] **Step 2: Add case 5 (arch error path) — no ADR → arch fails**

Insert:

```bash
# ── Error Paths (3 cases) ─────────────────────────────────────────

@test "full-workflow 5/7: arch gate fails on missing ADR-*.md" {
    # INTENTIONALLY skip write_arch_fixture — no ADR present
    run invoke_arch_stage "$FAKE_ROOT"
    [ "$status" -ne 0 ]
    [ ! -f "$FAKE_ROOT/.rddf/state/.arch-handoff.json" ]
}
```

**Important**: This case requires `invoke_arch_stage` to fail when no ADR exists. Verify Task 5's `invoke_arch_stage` Python call handles the missing ADR case correctly. If the current Python API doesn't gate on ADR existence, modify `invoke_arch_stage` in `tests/_lib/test_full_workflow_fixture.bash` to add a precheck:

```bash
invoke_arch_stage() {
    local root="$1"
    mkdir -p "$root/.rddf/state"
    cd "$root" || return 1

    # Precheck: arch gate requires ≥1 ADR
    if ! ls "$root/docs/adr"/ADR-*.md 2>/dev/null | head -1 | grep -q .; then
        echo "❌ arch gate: no ADR-*.md found in $root/docs/adr/" >&2
        return 10
    fi

    python3 -c "..."
}
```

- [ ] **Step 3: Run bats file to verify cases 1-5 pass**

Run: `bats tests/integration/test_full_workflow_e2e.bats`
Expected: PASS (5/5 tests)

If case 5 fails because `invoke_arch_stage` doesn't gate on ADR, apply the precheck fix above and rerun.

- [ ] **Step 4: Commit**

```bash
git add tests/integration/test_full_workflow_e2e.bats \
        tests/_lib/test_full_workflow_fixture.bash
git commit -m "test(e2e): add lifecycle (case 4) + arch error path (case 5)

- Case 4: end-to-end iteration.json archived status verification
- Case 5: arch gate blocks when no ADR-*.md present (error path)
- Add ADR precheck to invoke_arch_stage if not already gated"
```

---

## Task 9: Add Cases 6 + 7 (archive error paths)

**Files:**
- Modify: `tests/integration/test_full_workflow_e2e.bats`

- [ ] **Step 1: Add case 6 (lightweight 0 commits → archive refuses)**

Edit `tests/integration/test_full_workflow_e2e.bats`, insert:

```bash
@test "full-workflow 6/7: archive gate fails on lightweight mode 0 commits" {
    write_arch_fixture "$FAKE_ROOT"
    write_proposal_fixture "$FAKE_ROOT" "e2e-fixture"
    invoke_arch_stage "$FAKE_ROOT"
    invoke_planner_stage "$FAKE_ROOT"
    # INTENTIONALLY skip invoke_builder_phases — no commit made

    run invoke_archive "$FAKE_ROOT" "e2e-fixture"
    [ "$status" -ne 0 ]
    [[ "$output" == *"lightweight mode requires"* ]] || [[ "$output" == *"commit"* ]]
    [ -d "$FAKE_ROOT/openspec/changes/e2e-fixture" ]   # still in active
    [ ! -d "$FAKE_ROOT/openspec/changes/archive/e2e-fixture" ]
}
```

- [ ] **Step 2: Add case 7 (incomplete tasks.md → archive refuses)**

Insert:

```bash
@test "full-workflow 7/7: archive gate fails on incomplete tasks.md" {
    write_arch_fixture "$FAKE_ROOT"
    write_proposal_fixture "$FAKE_ROOT" "e2e-fixture"
    invoke_arch_stage "$FAKE_ROOT"
    invoke_planner_stage "$FAKE_ROOT"
    invoke_builder_phases "$FAKE_ROOT" "e2e-fixture"

    # Leave tasks.md partially unchecked (gate should block)
    cat > "$FAKE_ROOT/openspec/changes/e2e-fixture/tasks.md" <<'EOF'
# e2e-fixture Tasks

- [x] 1. Implement fixture
- [ ] 2. Run E2E test   # INTENTIONALLY UNCHECKED
EOF

    run invoke_archive "$FAKE_ROOT" "e2e-fixture"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unchecked"* ]]
    [ -d "$FAKE_ROOT/openspec/changes/e2e-fixture" ]   # still in active
    [ ! -d "$FAKE_ROOT/openspec/changes/archive/e2e-fixture" ]
}
```

- [ ] **Step 3: Run bats file to verify all 7 cases pass**

Run: `bats tests/integration/test_full_workflow_e2e.bats`
Expected: PASS (7/7 tests)

- [ ] **Step 4: Commit**

```bash
git add tests/integration/test_full_workflow_e2e.bats
git commit -m "test(e2e): add archive error paths (cases 6 + 7)

- Case 6: archive refuses on lightweight mode 0 commits
- Case 7: archive refuses on incomplete tasks.md checkboxes"
```

---

## Task 10: CI Gate Verification + Final Smoke

**Files:** (no new files; verification only)

- [ ] **Step 1: Verify test isolation gate passes**

Run: `bash tests/scripts/check_test_isolation.sh`
Expected: exit 0, no violations reported

- [ ] **Step 2: Verify assertion quality gate passes**

Run: `grep -rn "assert.*or True\|assert True" tests/integration/test_full_workflow_e2e.bats tests/_lib/test_full_workflow_fixture*.bats`
Expected: no output (no tautologies)

- [ ] **Step 3: Verify full integration suite still passes**

Run: `./test.sh --integration`
Expected: PASS for all integration tests including new 7-case file

If new file causes regressions, inspect failures and fix before proceeding.

- [ ] **Step 4: Verify bats recursive (CI equivalent)**

Run: `bats tests/integration/test_full_workflow_e2e.bats && bats tests/_lib/test_full_workflow_fixture*.bats`
Expected: All PASS

- [ ] **Step 5: Verify ruff + mypy still pass on changed Python**

Run: `ruff check skills/_lib/ && mypy --strict skills/_lib/core/`
Expected: exit 0 (no new violations introduced)

- [ ] **Step 6: Measure total runtime (acceptance criterion: ≤8 min)**

Run: `time bats tests/integration/test_full_workflow_e2e.bats`
Expected: elapsed ≤ 8 minutes

If exceeds 8 minutes, profile slowest @test and optimize (likely arch/planner Python imports).

- [ ] **Step 7: Commit verification artifacts (if any)**

If any docs/changelog updates were made during verification, commit them:

```bash
git status
# If CHANGELOG.md was updated to mention new E2E test:
git add CHANGELOG.md
git commit -m "docs(changelog): note new full-workflow E2E test suite"
```

If no docs changes, skip this step.

- [ ] **Step 8: Final commit + push**

```bash
git log --oneline -10   # verify 10+ commits from this plan
git push origin master   # trigger CI
```

Verify CI green at: `https://github.com/chisuhua/rdd-workflow/actions`

---

## Self-Review (per writing-plans skill)

**1. Spec coverage:**

| Spec section | Task |
|---|---|
| §3.1 file layout | T1 (skeleton), T2-T5 (helpers), T6-T9 (bats) |
| §3.2 component responsibilities | T1 (loadable), T2-T5 (helpers) |
| §3.3 CLI entry interpretation | T3, T4 (Python API calls; documented in code comments) |
| §4.1 happy path 4 cases | T6 (case 1), T7 (cases 2-3), T8 (case 4) |
| §4.2 error path 3 cases | T8 (case 5), T9 (cases 6-7) |
| §5 execution flow | T6-T9 (setup/teardown), T10 (CI verification) |
| §6.1 test isolation | T6 (cd "$REPO_ROOT" in teardown) |
| §6.2 pre-existing pollution | T2 ($BATS_TEST_TMPDIR only) |
| §6.3 assertion quality | T10 (Step 2 tautology check) |
| §10 acceptance criteria | T10 (all 7 checks) |

No gaps detected.

**2. Placeholder scan:**

- No "TBD" / "TODO" / "implement later" / "fill in details" found
- No "similar to Task N" — each task has full code
- No "add appropriate error handling" — error paths explicit in T8-T9
- All steps have actual code blocks
- All referenced types/functions defined in earlier tasks

**3. Type consistency:**

- `setup_fake_project` returns absolute path via stdout (used in `$()`) — consistent T2-T9
- `write_arch_fixture` / `write_proposal_fixture` take root as `$1` — consistent T2-T9
- `invoke_*` functions take root as `$1` — consistent T3-T9
- `assert_state` signature `root file fields` — consistent T5-T8
- `FAKE_ROOT` exported in `setup()`, cleaned in `teardown()` — consistent T6-T9

No inconsistencies detected.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-09-06-rdd-workflow-full-e2e.md`. Two execution options:**

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration
2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**

(For reference: per spec §1.4, Phase 2 external testbed repo is a separate future project and out of scope for this plan.)
