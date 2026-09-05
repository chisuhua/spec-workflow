#!/usr/bin/env bats
# tests/_lib/test_full_workflow_fixture_archive.bats
# Verify invoke_archive + assert_state behavior.

load ../test_helper
load_lib test_full_workflow_fixture

@test "invoke_archive: happy path moves change to openspec/changes/archive/" {
    FAKE_ROOT=$(setup_fake_project)
    write_arch_fixture "$FAKE_ROOT"
    write_proposal_fixture "$FAKE_ROOT" "e2e-fixture"
    invoke_arch_stage "$FAKE_ROOT"
    invoke_planner_stage "$FAKE_ROOT"
    invoke_builder_phases "$FAKE_ROOT" "e2e-fixture"
    sed -i 's/^- \[ \]/- [x]/g' "$FAKE_ROOT/openspec/changes/e2e-fixture/tasks.md"
    invoke_archive "$FAKE_ROOT" "e2e-fixture"
    [ -f "$FAKE_ROOT/openspec/changes/archive/e2e-fixture/proposal.md" ]
    [ ! -d "$FAKE_ROOT/openspec/changes/e2e-fixture" ]
    rm -rf "$FAKE_ROOT"
}

@test "invoke_archive: lightweight 0 commits → exit non-zero + commit-related error" {
    FAKE_ROOT=$(setup_fake_project)
    write_arch_fixture "$FAKE_ROOT"
    write_proposal_fixture "$FAKE_ROOT" "e2e-fixture"
    invoke_arch_stage "$FAKE_ROOT"
    invoke_planner_stage "$FAKE_ROOT"
    run invoke_archive "$FAKE_ROOT" "e2e-fixture"
    [ "$status" -ne 0 ]
    [[ "$output" == *"commit"* ]] || [[ "$stderr" == *"commit"* ]]
    [ -d "$FAKE_ROOT/openspec/changes/e2e-fixture" ]
    [ ! -d "$FAKE_ROOT/openspec/changes/archive/e2e-fixture" ]
    rm -rf "$FAKE_ROOT"
}

@test "assert_state: validates schema fields on .arch-handoff.json" {
    FAKE_ROOT=$(setup_fake_project)
    write_arch_fixture "$FAKE_ROOT"
    invoke_arch_stage "$FAKE_ROOT"
    assert_state "$FAKE_ROOT" ".arch-handoff.json" "schema_version:3|adr_dir:docs/adr"
    rm -rf "$FAKE_ROOT"
}
