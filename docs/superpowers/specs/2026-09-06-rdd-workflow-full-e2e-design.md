# rdd-workflow Full-Workflow E2E Test — Design

**Date**: 2026-09-06
**Status**: Draft (awaiting user review)
**Author**: brainstorming session output (Sisyphus orchestration)
**Decision Source**: User-selected options across 6 brainstorming questions (Hybrid plan, scope=3-stage+archive, scenarios=happy+error paths, mode=lightweight only, fixture=independent helper, CI=existing bats recursive, tech=pure bats+bash)

## 1. Problem & Motivation

### 1.1 Observed state (current E2E coverage gap)

Per `tests/integration/` audit (2026-09-06):

| Existing E2E test | Scope | Coverage |
|---|---|---|
| `test_v4_e2e_3_stage_flow.bats` | rdd-arch → rdd-planner → rdd-builder Python API handoff data contracts (10 cases, 418 行) | Data contract only — does NOT exercise CLI entry points |
| `test_global_install_external_project.bats` | Global install (`~/.agents/skills/`) entry surface from fake external project (19 cases, 359 行) | rddf CLI + resolver fallback — does NOT run a full workflow |
| `test_orchestrator_e2e_temp_project.py` | Orchestrator subprocess in temp project (201 行) | Orchestrator CLI only — does NOT cover per-stage flow |
| `test_rdd_verifier_e2e.bats`, `test_ac_verifier_e2e.bats`, `test_trigger_e2e.py` | Single-stage E2E | One stage each, no lifecycle |

**Gap**: No single test exercises the full happy-path lifecycle **rdd-arch → rdd-planner → rdd-builder → archive** with a fake project, nor any of the hard-block gates that fail at runtime.

### 1.2 Why this matters

1. **PR-level regressions go undetected** — API contracts can pass while user-facing flow breaks (e.g., wrong argument order, missing env var, gate check regressed).
2. **Hard-block gates have no regression lock** — `archive_gate_check` in `_lib/archive.sh` (worktree commits + tasks.md complete) is critical but only unit-tested.
3. **Real workflow breakage discovered by users**, not CI — currently a "user-experience E2E" requires a human walking through the docs.

### 1.3 Goal

Add a single bats E2E test file that, with a fake project under `$BATS_TEST_TMPDIR`, walks the canonical lifecycle:

```
fake project (git init + ADR + roadmap + openspec fixture)
   ↓
rdd-arch stage        → .arch-handoff.json (v3 schema, ADR-0016)
   ↓
rdd-planner stage     → .planner-handoff.json (v1 schema, §3.3)
   ↓
rdd-builder stages    → per-change handoff + iteration.json
   ↓
archive              → openspec/changes/<name>/ → openspec/changes/archive/
```

Plus 3 error-path cases covering the hard-block gates.

### 1.4 Non-goals (Phase 1)

- ❌ rdd-verifier 第 5 阶段（per ADR-0034, reserved for Phase 2）
- ❌ worktree 模式覆盖（lightweight-only per user decision）
- ❌ multi-change deps 场景
- ❌ 真实代码实现（fake project 只到 proposal/spec 阶段）
- ❌ 跨版本回归（留给 Phase 2 外部 testbed repo）
- ❌ 重构现有 `test_v4_e2e_3_stage_flow.bats`（保留作 Python API 覆盖，本测试新增作 CLI entry 覆盖）

## 2. Decisions Adopted (Q&A record)

User-confirmed across 6 brainstorming questions:

| Q | Decision |
|---|---|
| Q1 (Phase 1+2 strategy) | **Hybrid**: Phase 1 (本仓库) + Phase 2 (外部 testbed repo), sequential |
| Q2 (Phase 1 覆盖范围) | **CLI 入口 + 3 阶段 + archive**（rdd-arch → rdd-planner → rdd-builder → archive；不含 verifier） |
| Q3 (场景复杂度) | **单场景 + 错误路径**（happy path + 3 类错误路径） |
| Q4 (执行模式) | **只测 lightweight**（无 worktree，单 change） |
| Q5 (Fixture 组织) | **独立 fixture helper** (`tests/_lib/test_full_workflow_fixture.bash`) |
| Q6 (CI 集成) | **集成现有 bats recursive**（自动跑，每次 PR 必跑） |
| Q7 (实现技术) | **纯 bats + bash helper**（与 `test_v4_e2e_3_stage_flow.bats` 风格一致） |

## 3. Architecture

### 3.1 File layout

```
tests/
├── _lib/
│   └── test_full_workflow_fixture.bash       # NEW: 独立 fixture helper (~150 行)
│       ├── setup_fake_project()              # mktemp -d + git init + package.json
│       ├── write_arch_fixture()              # docs/adr/ + roadmap.md + arch docs
│       ├── write_proposal_fixture()          # openspec/changes/<name>/{proposal.md, tasks.md}
│       ├── invoke_arch_stage()               # 调 rdd-arch 入口 bash helpers
│       ├── invoke_planner_stage()            # 调 rdd-planner 入口 bash helpers
│       ├── invoke_builder_phases()           # 调 rdd-builder phase 0-3 helpers
│       ├── invoke_archive()                  # 调 archive.sh 入口
│       └── assert_state()                    # jq/grep 校验 .rddf/state/*.json
└── integration/
    └── test_full_workflow_e2e.bats           # NEW: bats 主测试 (~300 行, 7 cases)

docs/superpowers/specs/
└── 2026-09-06-rdd-workflow-full-e2e-design.md  # 本文档
```

### 3.2 Component responsibilities

**`tests/_lib/test_full_workflow_fixture.bash`**

- Reusable across multiple `@test` cases
- Mirrors pattern of `tests/_lib/skill.bash` (DRY helper for skill frontmatter parsing)
- Sourced via `load test_helper` + `load_lib test_full_workflow_fixture` (per `tests/test_helper.bash:23-39` `load_lib` resolver)
- Idempotent: each `setup_fake_project` returns a fresh `$FAKE_PROJECT_ROOT`
- Cleanup: bats `teardown()` + `$BATS_TEST_TMPDIR` auto-clean

**`tests/integration/test_full_workflow_e2e.bats`**

- Single file, 7 `@test` cases
- Loads `test_helper` + fixture helper
- Each case: `setup()` → invoke → assert → `teardown()` (bats native)
- Assertion style: `assert_file_exists`, `assert_file_contains`, `assert_cmd_succeeds` (from `tests/test_helper.bash:42-58`)

### 3.3 "CLI 入口" interpretation

In bats context, "CLI 入口" means **直接调用各阶段的入口 bash 脚本**（`skills/rdd-arch/scripts/*.sh` 等），不通过 OpenCode runtime 的 `skill_use("rdd-arch")` 包装层。这等同于"用户视角的 skill_use 调用会触发的同一组 helper 调用"，但去掉了 OpenCode session binding 等测试环境无依赖的环节。

| 用户视角 | 测试视角 |
|---|---|
| `skill_use("rdd-arch")` | `bash skills/rdd-arch/scripts/arch_env_check.sh && bash skills/rdd-arch/scripts/write_arch_handoff.sh ...` |
| `skill_use("rdd-planner")` | `bash skills/rdd-planner/scripts/planner_stage_entry.sh && bash skills/rdd-planner/scripts/planner_stage_exit.sh ...` |
| `skill_use("rdd-builder")` | `bash skills/rdd-builder/scripts/builder_phase_*.sh ...` |
| 用户最终执行 archive | `bash skills/_lib/archive.sh::archive_change` |

> **Why this is acceptable**: `skill_use` 在 OpenCode runtime 里的语义是"source SKILL.md, 执行顶层 instructions"。SKILL.md 里 instructions 又调用 `_lib/*.sh` 和 `skills/*/scripts/*.sh`。因此 bats 直接调底层 bash helpers 与用户 `skill_use` 在功能上等价,只是少了 OpenCode session 上下文初始化。Session binding 的语义由 `rddf-session` skill 单独测试覆盖。

## 4. Test Cases (7 cases, ~5-8 minutes total)

### 4.1 Happy path (4 cases)

| # | Case name | What it does | Key assertions |
|---|---|---|---|
| 1 | `arch: arch-done writes .arch-handoff.json (v3 schema per ADR-0016)` | setup_fake_project + 1 ADR + roadmap + invoke_arch_stage | `.rddf/state/.arch-handoff.json` exists; JSON has `schema_version=3`, `discovered.adr_dir`, `discovered.roadmap_path` |
| 2 | `planner: stage entry/exit writes .planner-handoff.json (v1 schema)` | case 1 + write_proposal_fixture + invoke_planner_stage | `.rddf/state/.planner-handoff.json` exists; JSON has `schema_version=1`, `owner=rdd-planner`, `discovered_roadmap_path` |
| 3 | `builder: phases 0-3 complete + archive moves change to openspec/archive/` | case 2 + invoke_builder_phases + invoke_archive | `.rddf/state/builder/<change>.json` exists; `iteration.json` `status=archived`; `openspec/changes/archive/<change>/proposal.md` exists; `openspec/changes/<change>/` no longer exists |
| 4 | `lifecycle: full flow ends with iteration.json status=archived and zero openspec/changes/* (active)` | end-to-end (no skips) | `jq -r '.sprints[-1].status' iteration.json == 'archived'`; `ls openspec/changes/*/proposal.md 2>/dev/null \| wc -l` == 0 |

### 4.2 Error paths (3 cases)

| # | Case name | What it does | Key assertions |
|---|---|---|---|
| 5 | `arch gate fails: missing ADR-*.md → arch-done blocks` | setup_fake_project WITHOUT any ADR + invoke_arch_stage | arch-done returns `exit != 0`; stderr contains `arch-quality-gate` or `ADR` reference; `.arch-handoff.json` NOT written |
| 6 | `archive gate fails: lightweight mode 0 commits → archive refuses` | full happy path WITHOUT executing any commit + invoke_archive | archive returns `exit != 0`; stderr contains `check_worktree_commits` or `0 commits`; `iteration.json` status remains `executing` |
| 7 | `archive gate fails: tasks.md incomplete (- [ ] remaining) → archive refuses` | full happy path WITH tasks.md partially unchecked + invoke_archive | archive returns `exit != 0`; stderr contains `tasks.md` or `incomplete`; `iteration.json` status remains `executing` |

### 4.3 Estimated timing

| Phase | Estimated time per case |
|---|---|
| arch (case 1, 5) | 15-30s |
| planner (case 2) | 30-60s |
| builder (case 3, 4, 6, 7) | 60-90s |
| **Total (7 cases)** | **~5-8 minutes** |

This is consistent with existing `test_v4_e2e_3_stage_flow.bats` (~5min for 10 cases), so no CI-time pressure spike.

## 5. Execution Flow

### 5.1 Single @test internal flow

```bash
@test "arch: arch-done writes .arch-handoff.json (v3 schema per ADR-0016)" {
    # 1. setup (auto, via setup())
    #    FAKE_PROJECT_ROOT=$(setup_fake_project)
    #    write_arch_fixture "$FAKE_PROJECT_ROOT"

    # 2. invoke (test logic)
    run invoke_arch_stage "$FAKE_PROJECT_ROOT"
    assert_cmd_succeeds    # exit 0

    # 3. assert (state verification)
    assert_file_exists "$FAKE_PROJECT_ROOT/.rddf/state/.arch-handoff.json"
    run cat "$FAKE_PROJECT_ROOT/.rddf/state/.arch-handoff.json"
    [[ "$output" =~ '"schema_version": 3' ]]
    [[ "$output" =~ '"adr_dir"' ]]
    [[ "$output" =~ '"roadmap_path"' ]]
}
```

### 5.2 CI integration

No CI workflow change required. `tests/integration/test_full_workflow_e2e.bats` is auto-picked up by the existing CI step:

```yaml
# .github/workflows/test.yml:79
- name: Run bats tests
  run: bats tests/ --recursive
```

CI time impact: +5-8 minutes per PR (acceptable; current total ~10min → ~15-18min).

### 5.3 Local dev

```bash
# Run only this file
bats tests/integration/test_full_workflow_e2e.bats

# Run via project test runner
./test.sh tests/integration/test_full_workflow_e2e.bats

# Run full integration suite
./test.sh --integration
```

## 6. Error Handling

### 6.1 Test isolation

Per `tests/scripts/check_test_isolation.sh` (CI gate, line 18-26 of `check_test_isolation.sh` header): tests MUST NOT use `os.chdir()` patterns that leave cwd pointing to a deleted temp dir. Implementation MUST use:

```bash
setup() {
    FAKE_PROJECT_ROOT="$(mktemp -d)"
    export FAKE_PROJECT_ROOT   # 子函数可访问
    cd "$FAKE_PROJECT_ROOT"   # 用 pushd/popd 或 setup/teardown 配对
}
teardown() {
    cd "$REPO_ROOT"           # 关键: 离开前 cd 回 repo root
    rm -rf "$FAKE_PROJECT_ROOT"
}
```

### 6.2 Pre-existing pollution

Per `test_global_install_external_project.bats:42-46` pattern: tests MUST NOT delete `$REPO_ROOT/.rddf/` state because other bats tests rely on stale state. The fixture helper uses `$BATS_TEST_TMPDIR` (auto-cleaned by bats) — never `$REPO_ROOT/.rddf/state/`.

### 6.3 Assertion quality

CI gate at `.github/workflows/test.yml:30-37` bans `assert.*or True\|assert True` tautologies. All `assert_*` helpers in `tests/test_helper.bash:42-58` use real conditional checks.

## 7. Testing Strategy

### 7.1 Coverage matrix

| Layer | Existing | New (this spec) |
|---|---|---|
| Pure function unit | `_lib/*.py` (Python unit, 57 files) | — |
| Bash helper unit | `tests/_lib/test_*.bats` (skill.bash, worktree.sh) | — |
| Per-stage CLI integration | `test_rdd_arch_cli.bats`, `test_planner_cmd.bats`, `test_builder_phase_*.bats` | — |
| **Cross-stage Python API E2E** | `test_v4_e2e_3_stage_flow.bats` (10 cases, 418 行) | — |
| **Cross-stage CLI entry E2E** | ❌ **MISSING** | ✅ `test_full_workflow_e2e.bats` (7 cases, ~300 行) |
| Single-stage E2E | `test_rdd_verifier_e2e.bats`, `test_ac_verifier_e2e.bats`, `test_trigger_e2e.py` | — |
| Hub-Spoke federation | `test_cross_repo_*.bats`, `test_contract_check_cli.bats` | — |

### 7.2 Relationship to existing tests

- **`test_v4_e2e_3_stage_flow.bats` (existing)**: covers Python API (`write_arch_handoff()`, `planner_stage_entry()`, `builder_*()` functions). Stays unchanged.
- **`test_full_workflow_e2e.bats` (new)**: covers CLI entry points (the bash wrappers that the Python functions delegate to). Complementary, not duplicative.

This split mirrors the existing `test_*_skill.bats` (structural) vs `test_*_subagent.bats` (functional) pattern.

## 8. Phase 2 Roadmap (Out of Scope for This Spec)

Per Q1 user decision, **Phase 2** (external `chisuhua/rdd-workflow-e2e-testbed` GitHub repo) is a future project. This spec only commits to Phase 1.

Phase 2 candidate features (NOT to be implemented as part of this spec):

- External testbed repo with multi-scenario fixtures (web app, CLI tool, library, monorepo)
- Visual progression dashboard
- Multi-version regression matrix (test N rdd-workflow versions against M fixtures)
- Long-term dogfooding reference implementation
- 跨仓库 CI 验证（Hub-Spoke federation E2E）

Phase 2 should be a **separate spec document** with its own brainstorming + design cycle, after Phase 1 has been validated by ≥2 weeks of CI green runs.

## 9. Open Questions / Risks

### 9.1 Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| `rdd-arch/scripts/*.sh` API drift between rdd-workflow versions | Medium | Pin to specific scripts in fixture helper; integration test asserts against `jq` schema fields not raw text |
| arch-done gate behavior changes (e.g., new gate added) | Medium | Document gate list in fixture helper; rerun fixture on every rdd-arch release |
| archive.sh hard-block gates relaxed in future | Low | Each error path case locks ONE specific gate; gate changes require explicit test update + ADR |
| CI time regression (5-8 min per PR) | Low | Run order: error-path cases first (fail-fast); happy-path last (long-running) |

### 9.2 Open questions (non-blocking)

- Q: Should happy-path case 3 commit to a real branch (`openspec/<change>`) in fake project, or just touch files?
  - Decision: touch files (lightweight mode simulation). No branch creation.
- Q: Should case 6 (0 commits archive failure) simulate via no-commit OR via explicit empty commit?
  - Decision: no-commit. Spec literal: "0 commits" means commit never executed.

## 10. Acceptance Criteria

This spec is "done" when:

- [ ] `tests/integration/test_full_workflow_e2e.bats` exists with 7 `@test` cases
- [ ] `tests/_lib/test_full_workflow_fixture.bash` exists with 8 helper functions
- [ ] `bats tests/integration/test_full_workflow_e2e.bats` passes locally
- [ ] `./test.sh --integration` passes locally
- [ ] CI `bats tests/ --recursive` step remains green
- [ ] `tests/scripts/check_test_isolation.sh` does not flag any test pollution
- [ ] No `assert.*or True` / `assert True` tautologies introduced
- [ ] 7 cases cover all happy path + 3 documented error paths
- [ ] Total runtime ≤ 8 minutes on CI
- [ ] Existing `test_v4_e2e_3_stage_flow.bats` (Python API) NOT modified

## 11. References

### Internal references

- `tests/test_helper.bash:23-39` — `load_lib` resolver
- `tests/test_helper.bash:42-58` — `assert_*` helpers
- `tests/integration/test_v4_e2e_3_stage_flow.bats` — pattern reference (Python API E2E)
- `tests/integration/test_global_install_external_project.bats:22-46` — fake external project pattern
- `tests/scripts/check_test_isolation.sh` — test pollution gate
- `.github/workflows/test.yml:79` — `bats tests/ --recursive` integration point
- `AGENTS.md` — "Worktree Commit Flow" (lightweight vs worktree mode decision)
- `AGENTS.md` §"Archive 前全量回归门" — regression gate policy

### ADR references

- ADR-0016: arch discovery contract (`.arch-handoff.json` v3 schema)
- ADR-0024: deps-driven execution mode (lightweight vs worktree)
- ADR-0028: role model per phase (role boundaries)
- ADR-0034: rdd-verifier 5th phase (excluded from Phase 1)

### Spec references

- `docs/superpowers/specs/2026-09-04-rdd-workflow-v4-architecture-stage-merge.md` — v4 stage definition (本 spec 与其 stage 划分一致)
- `docs/superpowers/specs/2026-08-05-guide-ship-execution-contract.md` — execution contract (task/plan relationship)
