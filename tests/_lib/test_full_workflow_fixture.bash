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
#
# Python invocation pattern: per AGENTS.md §20 Oracle C1, NEVER use
# `python3 -c "...$VAR..."` string interpolation. Use env-var passing via
# the standard 3-file pattern: {shim}.sh / {shim}.py / {shim}.env.py.
# For test-only helpers, we use the simpler `E2E_*` env-var pattern
# documented in the helper wrappers below.

# Stub functions (populated in subsequent tasks T2-T5)
setup_fake_project() { :; }
write_arch_fixture() { :; }
write_proposal_fixture() { :; }
invoke_arch_stage() { :; }
invoke_planner_stage() { :; }
invoke_builder_phases() { :; }
invoke_archive() { :; }
assert_state() { :; }
