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

@test "full-workflow 2/7: planner stage writes .planner-handoff.json (v1 schema)" {
    write_arch_fixture "$FAKE_ROOT"
    invoke_arch_stage "$FAKE_ROOT"
    invoke_planner_stage "$FAKE_ROOT"

    assert_state "$FAKE_ROOT" ".planner-handoff.json" \
        "schema_version:1|owner:rdd-planner"
}

@test "full-workflow 3/7: builder phases + archive moves change to openspec/changes/archive/" {
    write_arch_fixture "$FAKE_ROOT"
    write_proposal_fixture "$FAKE_ROOT" "e2e-fixture"
    invoke_arch_stage "$FAKE_ROOT"
    invoke_planner_stage "$FAKE_ROOT"
    invoke_builder_phases "$FAKE_ROOT" "e2e-fixture"
    sed -i 's/^- \[ \]/- [x]/g' "$FAKE_ROOT/openspec/changes/e2e-fixture/tasks.md"
    invoke_archive "$FAKE_ROOT" "e2e-fixture"

    [ -f "$FAKE_ROOT/openspec/changes/archive/e2e-fixture/proposal.md" ]
    [ ! -d "$FAKE_ROOT/openspec/changes/e2e-fixture" ]
}

@test "full-workflow 4/7: lifecycle ends with iteration.json status=archived, zero active changes" {
    write_arch_fixture "$FAKE_ROOT"
    write_proposal_fixture "$FAKE_ROOT" "e2e-fixture"
    invoke_arch_stage "$FAKE_ROOT"
    invoke_planner_stage "$FAKE_ROOT"
    invoke_builder_phases "$FAKE_ROOT" "e2e-fixture"
    sed -i 's/^- \[ \]/- [x]/g' "$FAKE_ROOT/openspec/changes/e2e-fixture/tasks.md"
    invoke_archive "$FAKE_ROOT" "e2e-fixture"

    run jq -r '.sprints[-1].status' "$FAKE_ROOT/.rddf/state/iteration.json"
    [ "$output" = "archived" ]

    local active_count
    active_count=$(find "$FAKE_ROOT/openspec/changes" -maxdepth 2 -name proposal.md -not -path "*/archive/*" | wc -l)
    [ "$active_count" -eq 0 ]
}

@test "full-workflow 5/7: arch gate fails on missing ADR-*.md" {
    run invoke_arch_stage "$FAKE_ROOT"
    [ "$status" -ne 0 ]
    [ ! -f "$FAKE_ROOT/.rddf/state/.arch-handoff.json" ]
}

@test "full-workflow 6/7: archive gate fails on lightweight mode 0 commits" {
    write_arch_fixture "$FAKE_ROOT"
    write_proposal_fixture "$FAKE_ROOT" "e2e-fixture"
    invoke_arch_stage "$FAKE_ROOT"
    invoke_planner_stage "$FAKE_ROOT"

    run invoke_archive "$FAKE_ROOT" "e2e-fixture"
    [ "$status" -ne 0 ]
    [[ "$output" == *"commit"* ]] || [[ "$stderr" == *"commit"* ]]
    [ -d "$FAKE_ROOT/openspec/changes/e2e-fixture" ]
    [ ! -d "$FAKE_ROOT/openspec/changes/archive/e2e-fixture" ]
}

@test "full-workflow 7/7: archive gate fails on incomplete tasks.md" {
    write_arch_fixture "$FAKE_ROOT"
    write_proposal_fixture "$FAKE_ROOT" "e2e-fixture"
    invoke_arch_stage "$FAKE_ROOT"
    invoke_planner_stage "$FAKE_ROOT"
    invoke_builder_phases "$FAKE_ROOT" "e2e-fixture"

    cat > "$FAKE_ROOT/openspec/changes/e2e-fixture/tasks.md" <<'EOF'
# e2e-fixture Tasks

- [x] 1. Implement fixture
- [ ] 2. Run E2E test
EOF

    run invoke_archive "$FAKE_ROOT" "e2e-fixture"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unchecked"* ]] || [[ "$stderr" == *"unchecked"* ]]
    [ -d "$FAKE_ROOT/openspec/changes/e2e-fixture" ]
    [ ! -d "$FAKE_ROOT/openspec/changes/archive/e2e-fixture" ]
}
