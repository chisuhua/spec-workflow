#!/usr/bin/env bats
# tests/_lib/test_full_workflow_fixture_skeleton.bats
# Skeleton test: verify fixture helper is loadable + exports expected functions.

load ../test_helper

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
