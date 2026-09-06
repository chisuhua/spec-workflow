# rdd-workflow Full-Workflow E2E Test — Design v2 (Real Path)

**Date**: 2026-09-06
**Status**: Revision (replaces `2026-09-06-rdd-workflow-full-e2e-design.md` after review)
**Author**: post-review refactor (Sisyphus orchestration)
**Review trigger**: 5-agent parallel review found 3 blocking issues — test was self-contained simulator with no production code coverage; fixture payload diverged from real `_lib/schemas/` contracts; archive gate semantics invented vs real `_lib/archive.sh`.

## 1. Problem & Motivation (revised)

### 1.1 What the v1 spec got wrong

The v1 spec (`eef9378`) called for "CLI entry + 3 stages + archive" coverage, but the implementation was a self-contained Python runner (`e2e_stage_runner.py`) that:

1. Re-implemented all 3 stage emissions in fake code (no call to real `skills.rdd_arch.scripts.write_arch_handoff.write_arch_handoff()`)
2. Emitted handoff JSON with fictional keys (`schema_version`, `sprints`) that don't match real `_lib/schemas/{arch,planner,builder,iteration}_handoff_schema.json`
3. Re-implemented archive gate in bash inside the fixture helper with divergent thresholds (≥2 commits, zero-unchecked) vs real `_lib/archive.sh::archive_gate_check` (≥1 completed task)

Result: 18/18 tests passed mechanically, but the suite has **zero production regression value** for the stated goal of "locking hard-block gates in `_lib/archive.sh`" (background §1.2.2).

### 1.2 What v2 must achieve

Replace every self-contained fake with **real function invocation** for the canonical contract surface, while keeping bats test mechanics and `$BATS_TEST_TMPDIR` isolation:

| Stage | v1 (fake) | v2 (real) |
|---|---|---|
| arch | `e2e_stage_runner.stage_arch()` | `python3 -m skills.rdd_arch.scripts.write_arch_handoff_env` (12 DISCOVERED_* env vars) |
| arch gate (error case) | inline precheck in fixture | source `arch_done_gate.sh` + call `check_arch_done_gate` |
| planner | `e2e_stage_runner.stage_planner()` | `python3 -m _lib.planner_handoff` (PROJECT_ROOT + 4 env vars) |
| builder handoff | `e2e_stage_runner.stage_builder()` | `_lib.builder_handoff.write_builder_handoff()` (Python module, called via env-py shim) |
| archive gate (error case) | bash re-implementation | source `_lib/archive.sh` + call `archive_gate_check <name> <root>` |
| archive happy path | bash re-implementation | `openspec archive <name> --yes` + `mark_iteration_archived` (real CLI + real Python) |
| assertions | `schema_version`, `sprints` | real contract keys: `version`, `schema`, `change_name`, `changes[].status` |

### 1.3 Non-goals (unchanged from v1)

- ❌ rdd-verifier 第 5阶段 (per ADR-0034, Phase 2)
- ❌ worktree 模式覆盖（lightweight-only per Q4 user decision）
- ❌ multi-change deps 场景
- ❌ 跨版本回归（Phase 2 外部 testbed）

## 2. Real Entry Points (the v2 invocation contract)

### 2.1 arch stage — `skills/rdd-arch/scripts/write_arch_handoff.sh`

Bash wrapper that calls the real Python writer via env-var passing (Oracle C1 safe). Function `write_arch_handoff()` lives at `skills/rdd_arch.scripts.write_arch_handoff.write_arch_handoff()`.

Required env vars (per `write_arch_handoff_env.py:24-37`):
- `PROJECT_ROOT` — absolute path to fake project root
- `DISCOVERED_ADR_DIR` (default `docs/adr`)
- `DISCOVERED_ROADMAP_PATH` (default `roadmap.md`)
- `DISCOVERED_ARCHITECTURE_DIR` (default `docs/architecture`)
- `DISCOVERED_ADR_PATTERN` (default `ADR-*.md`)
- `DISCOVERED_ADR_DIR_FOUND` (string `true`/`false`)
- `DISCOVERED_ROADMAP_FOUND`
- `DISCOVERED_ARCH_FOUND`
- `DISCOVERED_ADR_DIR_TRIED`, `DISCOVERED_ROADMAP_TRIED`, `DISCOVERED_ARCH_TRIED` (integers)
- `ROADMAP_EXISTS_BOOL`

Plus env vars to disable side-effects:
- `SKIP_WORKFLOW_REFLECTION=1` (skip reflect_engine hook)
- `SKIP_AUTO_PLANNER_FEEDBACK=1` (skip Wave 4 Change 2 hook)

Returns: writes `.rddf/state/.arch-handoff.json` with required keys per `_lib/schemas/arch_handoff_schema.json`:
- `version` (int 1/2/3) — NOT `schema_version`
- `arch_complete_at`, `adr_count`, `completed_adr_ids`, `current_phase`, `plan_started_at`
- `adr_dir`, `architecture_dir`, `adr_pattern`
- `discovered` (with `adr_dir` + `architecture_dir` subschemas)

### 2.2 arch gate — `skills/rdd-arch/scripts/arch_done_gate.sh`

Source the file, call `check_arch_done_gate`. Function reads `DISCOVERED_*` env vars (same set as above) and gates on ADR count ≥ 1 + roadmap.md exists.

For error case: set fake `DISCOVERED_*` env vars to point at fake project, source the script, call `check_arch_done_gate`. Returns 1 if either gate fails.

### 2.3 planner stage — `python3 -m _lib.planner_handoff`

Env-var mode (Oracle C1 safe). Reads from `_lib/planner_handoff.py:48-57`:
- `PROJECT_ROOT` (default cwd)
- `PROPOSALS_AUTHORED` (comma-separated → list)
- `PROPOSALS_APPROVED_COUNT` (int)
- `FEATURES_ACTIVE` (comma-separated → list)
- `CURRENT_SPRINT` (default `sprint-YYYY-MM`)

Returns: writes `.rddf/state/.planner-handoff.json` with required keys per `_lib/schemas/planner_handoff_schema.json`:
- `schema: "planner-handoff-v1"` (const)
- `version: 1` (const)
- `owner: "rdd-planner"` (const)
- `planner_complete_at`, `current_sprint`

We **bypass** `skills/rdd-planner/scripts/planner_stage_entry.sh` because it requires `rddf` CLI (not in bats test env). The Python entry is the canonical one.

### 2.4 builder handoff — `_lib/builder_handoff.write_builder_handoff`

Direct Python module call via env-py shim pattern (3-file split per AGENTS.md §20). Function signature per `_lib/builder_handoff.py:18-36`:

```python
write_builder_handoff(
    project_root: str,
    change_name: str,
    current_phase: str = "phase-0",      # enum: phase-0/1/1.5/2/2.5/3
    approval_status: str = "pending",     # enum: pending/approved/rejected/deferred/revising
    execution_mode_decision: dict = {},
    worktree_path: str = "",
    branch: str = "",
    ...
)
```

Returns handoff with required keys per `_lib/schemas/builder_handoff_schema.json`:
- `schema: "builder-handoff-v1"`, `version: 1`, `owner: "rdd-builder"`
- `change_name` (NOT `change`)
- `current_phase`, `retry_count`, `max_retries`

We **bypass** `skills/rdd-builder/scripts/phase{0..3}_*.sh` and `_lib/cli/builder_cmd.py` because they require `rddf` CLI + real openspec change dir + verifier. The Python writer is the canonical one (matches `test_v4_e2e_3_stage_flow.bats:120-146` pattern).

### 2.5 archive happy path — `openspec archive <name> --yes` + `mark_iteration_archived`

For lightweight mode (no worktree), the canonical archive flow per `_lib/archive.sh::archive_change:524-535`:

1. `switch_to_default_branch "$main_root" "$default_branch"` (handled by bats teardown `cd "$REPO_ROOT"`)
2. `openspec archive "$name" --yes` (real CLI, available in bats env: v1.4.1)
3. `cleanup_worktree_and_branch` (no-op for lightweight)
4. `commit_archive_moves` (auto-commit the moves)
5. `mark_iteration_archived "$name" "$main_root"` (real `_lib/iteration/post_archive.py`)

We invoke step 2 + step 5 directly in the bats context. Step 4 (commit) is optional; we do it via `git add . && git commit -m "archive(...)"`.

### 2.6 archive gate — `_lib/archive.sh::archive_gate_check`

Source the file, call `archive_gate_check <name> <tasks_root>`. Returns:
- 0 on success
- 1 if `FORCE_ARCHIVE_INCOMPLETE != yes` AND (tasks.md missing OR 0 completed `[x]`)
- 1 if verifier contract check fails (skippable via `SKIP_VERIFIER_CONTRACT=yes`)

Required env vars for the gate:
- `SKIP_VERIFIER_CONTRACT=yes` (skip the verifier sub-gate — Phase 1 doesn't test verifier)
- `SKIP_AC_VERIFICATION=yes` (skip ac-verifier sub-gate)
- `FORCE_ARCHIVE_INCOMPLETE=no` (default; gate active)

This is the **canonical real gate**, not a re-implementation.

## 3. Real Schema Contracts (the v2 assertion target)

All assertions must validate against these real schemas (not v1's fictional `schema_version`/`sprints`):

| File | Schema path | Required keys |
|---|---|---|
| `.arch-handoff.json` | `_lib/schemas/arch_handoff_schema.json` | `version` (int 1/2/3), `arch_complete_at`, `adr_count`, `completed_adr_ids`, `current_phase`, `plan_started_at`, `adr_dir`, `architecture_dir`, `adr_pattern`, `discovered` |
| `.planner-handoff.json` | `_lib/schemas/planner_handoff_schema.json` | `schema: "planner-handoff-v1"`, `version: 1`, `owner: "rdd-planner"`, `planner_complete_at`, `current_sprint` |
| `builder/<change>.json` | `_lib/schemas/builder_handoff_schema.json` | `schema: "builder-handoff-v1"`, `version: 1`, `owner: "rdd-builder"`, `change_name`, `current_phase`, `retry_count`, `max_retries` |
| `iteration.json` | `_lib/schemas/iteration_schema.json` | `version` (3-7), `updated_at`, `current_phase`, `changes` (NOT `sprints`) — each entry has `name`, `status` |

**Defense-in-depth**: every `@test` case that emits a handoff also runs `jsonschema.validate(payload, schema)` to lock the contract shape. Repo already depends on `jsonschema` (per `requirements.txt`).

## 4. Test Cases (7 cases — same count, real semantics)

### 4.1 Happy path (4 cases)

| # | Case | Real assertion |
|---|---|---|
| 1 | arch stage emits valid `.arch-handoff.json` | `version=3`, `adr_dir=docs/adr`, `current_phase=phase-1`, `discovered.adr_dir.found=true` + **jsonschema validate** |
| 2 | planner stage emits valid `.planner-handoff.json` | `schema=planner-handoff-v1`, `version=1`, `owner=rdd-planner`, `current_sprint=sprint-2026-09` + **jsonschema validate** |
| 3 | builder writes per-change handoff + real archive moves change | builder `change_name=e2e-fixture`, `current_phase=phase-3`, `archive_status=archived` + real `openspec archive` moves dir + **jsonschema validate** |
| 4 | full lifecycle ends with iteration.json updates | `changes[?name=e2e-fixture].status == "archived"`, `archived_at` set, no active `openspec/changes/<name>/` |

### 4.2 Error paths (3 cases — all real gate failures)

| # | Case | Real gate invoked |
|---|---|---|
| 5 | arch gate fails on missing ADR | `check_arch_done_gate` returns 1 + stderr contains `至少需要 1 个 ADR` (per `arch_done_gate.sh:47`) |
| 6 | archive gate fails on 0 completed tasks | `archive_gate_check <name> <root>` returns 1 + stderr contains `未实现 (0 个完成任务)` (per `archive.sh:393`) |
| 7 | archive gate fails on missing tasks.md | `archive_gate_check <name> <root>` returns 1 + stderr contains `tasks.md 缺失` (per `archive.sh:384`) |

### 4.3 Estimated timing (revised)

| Phase | Time per case |
|---|---|
| arch (cases 1, 5) | 5-10s |
| planner (case 2) | 3-5s |
| builder (case 3, 4) | 10-15s |
| archive error (cases 6, 7) | 5-8s |
| **Total (7 cases)** | **~60-80s** |

Real Python invocation adds ~3s vs fake (file system + atomic_write + FileLock overhead). All under 8-min budget.

## 5. Execution Flow (per @test)

### 5.1 Happy case 1 (arch)

```bash
@test "1/7: arch emits valid .arch-handoff.json (v3 contract per ADR-0016)" {
    write_arch_fixture "$FAKE_ROOT"
    invoke_arch_stage "$FAKE_ROOT"

    assert_state "$FAKE_ROOT" ".arch-handoff.json" \
        "version:3|adr_dir:docs/adr|current_phase:phase-1"
    assert_schema "$FAKE_ROOT" ".arch-handoff.json"  # NEW: jsonschema validate
}
```

### 5.2 Error case 5 (no ADR)

```bash
@test "5/7: arch gate blocks on missing ADR (real check_arch_done_gate)" {
    # INTENTIONALLY skip write_arch_fixture — no ADR
    run invoke_arch_gate "$FAKE_ROOT"
    [ "$status" -ne 0 ]
    [[ "$stderr" == *"至少需要 1 个 ADR"* ]]
    [ ! -f "$FAKE_ROOT/.rddf/state/.arch-handoff.json" ]
}
```

## 6. Error Handling (refined)

### 6.1 Test isolation (unchanged)

- All assertions in `$BATS_TEST_TMPDIR` (auto-cleaned)
- `teardown()`: `cd "$REPO_ROOT"` FIRST, then `rm -rf "$FAKE_ROOT"` (corrected v1 order)
- `unset FAKE_ROOT PROJECT_ROOT PROPOSALS_* DISCOVERED_*` in teardown

### 6.2 Pre-existing pollution (unchanged)

- All files in `$BATS_TEST_TMPDIR` — never touch `$REPO_ROOT/.rddf/state/`
- However, **we now exercise `_lib/schemas/*.json`** (read-only) which is a non-state-file reference — safe

### 6.3 Real function invocation safety

- Real Python modules may write to `<project_root>/.rddf/state/` — that's exactly the fake project's `.rddf/`, not the rdd-workflow repo's
- Real `openspec archive` mutates the fake project's `openspec/changes/` — also safe
- `_lib/iteration/post_archive.py` reads fake project's `.rddf/state/iteration.json` — safe

### 6.4 CI prerequisites (already met by package.json engines)

- `openspec` CLI v1.3.1+ (verified v1.4.1 in test env)
- `git` 2.25+
- `python3` 3.11+
- `jsonschema` Python package (already in `requirements.txt`)
- `jq` 1.6+ (for assertion JSON parsing)

## 7. Coverage Matrix (revised)

| Layer | v1 coverage | v2 coverage |
|---|---|---|
| `skills.rdd_arch.scripts.write_arch_handoff.write_arch_handoff()` | ❌ not invoked | ✅ invoked via env-py shim |
| `skills.rdd_arch.scripts.arch_done_gate.sh::check_arch_done_gate` | ❌ not invoked | ✅ invoked (error case 5) |
| `_lib.planner_handoff.write_planner_handoff()` | ❌ not invoked | ✅ invoked via `python3 -m _lib.planner_handoff` |
| `_lib.builder_handoff.write_builder_handoff()` | ❌ not invoked | ✅ invoked via env-py shim |
| `_lib.archive.sh::archive_gate_check` | ❌ not invoked | ✅ invoked (error cases 6, 7) |
| `openspec archive <name> --yes` | ❌ not invoked | ✅ invoked (happy case 3) |
| `_lib/iteration/post_archive.mark_iteration_archived` | ❌ not invoked | ✅ invoked (happy case 4) |
| Schema validation | ❌ fake keys | ✅ jsonschema validate against `_lib/schemas/*.json` |
| CLI plumbing (rddf, openspec sub-commands) | n/a | ❌ not covered (use Python entry directly) |

v2 covers the **Python contract surface** of each stage + the canonical archive flow + the canonical archive gate. CLI wrapping (rddf) is already covered by `test_rdd_arch_cli.bats` (74 lines, 6 cases) per its own scope.

## 8. Phase 2 Roadmap (Out of Scope)

Per v1 spec §8, Phase 2 external testbed repo deferred. No change.

## 9. Risks (revised)

| Risk | Likelihood | Mitigation |
|---|---|---|
| Real Python API signature drifts (rename params) | Medium | Pin to `_lib.builder_handoff.write_builder_handoff()` signature; mark schema validation as the regression lock |
| `openspec archive` CLI behavior changes | Low | Pin to v1.3.1+ in CI; assert only `openspec/changes/archive/<name>/` exists, not specific format |
| `_lib/archive.sh::archive_gate_check` adds new sub-gates | Medium | `SKIP_VERIFIER_CONTRACT=yes` + `SKIP_AC_VERIFICATION=yes` in teardown setup to neutralize non-task gates; documented in fixture header |
| iteration.json `version` enum bumps | Medium | jsonschema validate against `_lib/schemas/iteration_schema.json` enum (currently 3-7) — auto-tracks schema updates |

## 10. Acceptance Criteria

This revision is "done" when:

- [ ] `tests/_lib/e2e_stage_runner.py` REMOVED (replaced by real script invocation)
- [ ] `tests/_lib/test_full_workflow_fixture.bash` exports same 8 function names but each invokes REAL script/API
- [ ] All assertions use REAL schema keys (`version`, `schema`, `change_name`, `changes[].status`)
- [ ] Every handoff-emitting case additionally runs `jsonschema.validate()` against the matching schema file
- [ ] `tests/integration/test_full_workflow_e2e.bats` still has 7 cases (4 happy + 3 error), error cases invoke real `archive_gate_check` / `check_arch_done_gate`
- [ ] `tests/_lib/test_full_workflow_fixture_*.bats` (5 helper files, 11 cases) all pass against real-implementation fixture
- [ ] `bash tests/scripts/check_test_isolation.sh` does not flag new files
- [ ] No `assert.*or True` / `assert True` tautologies in new files
- [ ] Total runtime ≤ 2 minutes (improved from v1's 10s — real Python adds overhead)
- [ ] `git diff` from v1 shows: e2e_stage_runner.py removed, test_full_workflow_fixture.bash rewritten, bats files schema-key updated
- [ ] All 18 cases (7 E2E + 11 helper) pass

## 11. References (revised)

### Internal references (v2 entry points)
- `skills/rdd-arch/scripts/write_arch_handoff.sh` + `write_arch_handoff_env.py` (line 24-37)
- `skills/rdd-arch/scripts/arch_done_gate.sh` (line 16-67)
- `_lib/planner_handoff.py` (line 48-57)
- `_lib/builder_handoff.py` (line 18-36)
- `_lib/archive.sh::archive_gate_check` (line 360-479)
- `_lib/archive.sh::archive_change` (line 499-652) — lightweight path at 524-535
- `_lib/iteration/post_archive.py` (mark_iteration_archived)
- `openspec` CLI v1.3.1+ (`openspec archive <name> --yes`)

### ADR references
- ADR-0016: arch discovery contract (`.arch-handoff.json` v1 schema system, contract v3)
- ADR-0024: deps-driven execution mode
- ADR-0034: rdd-verifier 5th phase (excluded)
- ADR-0035: verifier-archive-gate boundary (we use `SKIP_VERIFIER_CONTRACT=yes` to bypass for Phase 1)

### Test conventions
- `tests/test_helper.bash:23-39` — `load_lib` resolver
- `tests/test_helper.bash:42-58` — `assert_*` helpers
- `tests/integration/test_v4_e2e_3_stage_flow.bats:98-114` — pattern reference for `python3 -m _lib.planner_handoff` env-var mode
- `tests/integration/test_v4_e2e_3_stage_flow.bats:120-146` — pattern reference for `_lib.builder_handoff.write_builder_handoff` Python call

### Spec references (supersedes)
- v1 spec `eef9378` (this design supersedes it)
- `docs/superpowers/specs/2026-09-04-rdd-workflow-v4-architecture-stage-merge.md` (v4 stage def)