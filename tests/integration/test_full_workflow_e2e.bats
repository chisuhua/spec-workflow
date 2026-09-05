#!/usr/bin/env bats
# tests/integration/test_full_workflow_e2e.bats
#
# Full-workflow E2E: fake project walks rdd-arch → rdd-planner →
# rdd-builder → archive lifecycle (lightweight mode).
#
# Per docs/superpowers/specs/2026-09-06-rdd-workflow-full-e2e-design.md
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
    [ -n "${FAKE_ROOT:-}" ] && [ -d "$FAKE_ROOT" ] && rm -rf "$FAKE_ROOT"
    cd "$REPO_ROOT"
}

@test "full-workflow 1/7: arch stage writes .arch-handoff.json (v3 schema per ADR-0016)" {
    write_arch_fixture "$FAKE_ROOT"
    invoke_arch_stage "$FAKE_ROOT"

    assert_state "$FAKE_ROOT" ".arch-handoff.json" \
        "schema_version:3|adr_dir:docs/adr|current_phase:phase-1"
}
