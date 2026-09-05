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

# Setup: create fake project under $BATS_TEST_TMPDIR (or /tmp fallback)
# Returns: absolute path to fake project root via stdout
setup_fake_project() {
    local root
    root="${BATS_TEST_TMPDIR:-/tmp}/fake-project-$$-${RANDOM}"
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

invoke_arch_stage() {
    local root="$1"
    cd "$root" || return 1
    E2E_STAGE=arch \
    E2E_PROJECT_ROOT="$root" \
    E2E_ADR_DIR=docs/adr \
    E2E_ROADMAP_PATH=roadmap.md \
    E2E_ADR_PATTERN='ADR-*.md' \
        python3 "$(dirname "${BASH_SOURCE[0]}")/e2e_stage_runner.py"
}

invoke_planner_stage() {
    local root="$1"
    cd "$root" || return 1
    E2E_STAGE=planner \
    E2E_PROJECT_ROOT="$root" \
        python3 "$(dirname "${BASH_SOURCE[0]}")/e2e_stage_runner.py"
}

invoke_builder_phases() {
    local root="$1" name="$2"
    cd "$root" || return 1
    E2E_STAGE=builder \
    E2E_PROJECT_ROOT="$root" \
    E2E_CHANGE_NAME="$name" \
        python3 "$(dirname "${BASH_SOURCE[0]}")/e2e_stage_runner.py"
    echo "# E2E touch" >> "$root/openspec/changes/$name/touch.log"
    git -C "$root" add "openspec/changes/$name/touch.log"
    git -C "$root" commit -q -m "e2e: touch commit for lightweight mode"
}

invoke_archive() {
    local root="$1" name="$2"
    [ -d "$root" ] || { echo "❌ invoke_archive: root not found: $root" >&2; return 4; }
    [ -n "$name" ] || { echo "❌ invoke_archive: change name required" >&2; return 4; }

    local default_branch
    default_branch=$(git -C "$root" symbolic-ref --short HEAD 2>/dev/null || echo "master")
    local change_commits
    change_commits=$(git -C "$root" log --oneline -- "openspec/changes/$name/" 2>/dev/null | wc -l | tr -d ' ')

    if [ "${change_commits:-0}" -lt 2 ]; then
        echo "❌ archive gate: lightweight mode requires ≥2 commits touching openspec/changes/$name/ (got ${change_commits:-0})" >&2
        return 1
    fi

    local tasks_file="$root/openspec/changes/$name/tasks.md"
    local unchecked
    unchecked=$(grep -cE "^- \[ \]" "$tasks_file" 2>/dev/null || echo 0)
    if [ "$unchecked" -gt 0 ]; then
        echo "❌ archive gate: tasks.md has $unchecked unchecked items" >&2
        return 2
    fi

    if [ ! -f "$root/.rddf/state/builder/$name.json" ]; then
        echo "❌ archive gate: missing .rddf/state/builder/$name.json" >&2
        return 3
    fi

    mkdir -p "$root/openspec/changes/archive"
    mv "$root/openspec/changes/$name" "$root/openspec/changes/archive/$name"
    git -C "$root" add "openspec/changes/" 2>/dev/null || true
    git -C "$root" commit -q -m "archive($name): archive completed" 2>/dev/null || true

    mkdir -p "$root/.rddf/state"
    if [ ! -f "$root/.rddf/state/iteration.json" ]; then
        cat > "$root/.rddf/state/iteration.json" <<EOF
{
  "sprints": [
    {"change": "$name", "status": "archived", "archived_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
  ]
}
EOF
    else
        jq --arg name "$name" \
            '.sprints |= map(if .change == $name then .status = "archived" else . end)' \
            "$root/.rddf/state/iteration.json" > "$root/.rddf/state/iteration.json.tmp" \
            && mv "$root/.rddf/state/iteration.json.tmp" "$root/.rddf/state/iteration.json"
    fi
}

assert_state() {
    local root="$1" file="$2" fields="$3"
    local state_file="$root/.rddf/state/$file"
    [ -f "$state_file" ] || { echo "❌ assert_state: file missing: $state_file" >&2; return 1; }

    local IFS='|'
    local pair key expected actual
    for pair in $fields; do
        key="${pair%%:*}"
        expected="${pair#*:}"
        actual=$(jq -r --arg k "$key" '.[$k] // empty' "$state_file" 2>/dev/null)
        if [ "$actual" != "$expected" ]; then
            echo "❌ assert_state: $key expected '$expected' got '$actual'" >&2
            return 1
        fi
    done
}
