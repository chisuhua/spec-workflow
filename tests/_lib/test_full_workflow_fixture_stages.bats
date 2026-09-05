#!/usr/bin/env bats
# tests/_lib/test_full_workflow_fixture_stages.bats
# Verify invoke_planner_stage + invoke_builder_phases behavior.
# Both use env-var pattern (Oracle C1 safe, per AGENTS.md §20).

load ../test_helper
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
    run jq -r '.owner' "$FAKE_ROOT/.rddf/state/builder/e2e-fixture.json"
    [ "$output" = "rdd-builder" ]
    run jq -r '.execution_mode' "$FAKE_ROOT/.rddf/state/builder/e2e-fixture.json"
    [ "$output" = "lightweight" ]
    rm -rf "$FAKE_ROOT"
}
