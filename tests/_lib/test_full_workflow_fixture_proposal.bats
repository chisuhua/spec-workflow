#!/usr/bin/env bats
# tests/_lib/test_full_workflow_fixture_proposal.bats
# Verify write_proposal_fixture + invoke_arch_stage behavior.
# invoke_arch_stage uses env-var passing (Oracle C1 safe, per AGENTS.md §20).

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

@test "invoke_arch_stage: writes .rddf/state/.arch-handoff.json with schema_version=3" {
    FAKE_ROOT=$(setup_fake_project)
    write_arch_fixture "$FAKE_ROOT"
    invoke_arch_stage "$FAKE_ROOT"
    [ -f "$FAKE_ROOT/.rddf/state/.arch-handoff.json" ]
    run jq -r '.schema_version' "$FAKE_ROOT/.rddf/state/.arch-handoff.json"
    [ "$output" = "3" ]
    run jq -r '.adr_dir' "$FAKE_ROOT/.rddf/state/.arch-handoff.json"
    [ "$output" = "docs/adr" ]
    run jq -r '.current_phase' "$FAKE_ROOT/.rddf/state/.arch-handoff.json"
    [ "$output" = "phase-1" ]
    rm -rf "$FAKE_ROOT"
}
