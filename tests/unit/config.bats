#!/usr/bin/env bats

setup() {
    load '../setup'
    setup
}

teardown() {
    teardown
}

# ─── interpolate ────────────────────────────────────────────────────────────

@test "interpolate replaces \${project} and \${session}" {
    result=$(interpolate 'claude ${project}-${session}' "myapp" "feat-1")
    [ "$result" = "claude myapp-feat-1" ]
}

@test "interpolate replaces port variables" {
    result=$(interpolate 'server on ${backend_port}' "myapp" "feat" "backend_port=8000")
    [ "$result" = "server on 8000" ]
}

@test "interpolate replaces multiple port variables" {
    result=$(interpolate '${backend_port} and ${frontend_port}' "p" "s" "backend_port=8000" "frontend_port=5173")
    [ "$result" = "8000 and 5173" ]
}

@test "interpolate leaves unknown variables intact" {
    result=$(interpolate '${project} and ${unknown_var}' "myapp" "s")
    [ "$result" = 'myapp and ${unknown_var}' ]
}

@test "interpolate with no port vars" {
    result=$(interpolate '${project}' "myapp" "s")
    [ "$result" = "myapp" ]
}

# ─── load_config ────────────────────────────────────────────────────────────

@test "load_config extracts project name" {
    load_config "$FIXTURE_DIR/simple.yml"
    [ "$CFG_PROJECT" = "simple-app" ]
}

@test "load_config extracts base_branch" {
    load_config "$FIXTURE_DIR/node-only.yml"
    [ "$CFG_BASE_BRANCH" = "develop" ]
}

@test "load_config defaults base_branch to main" {
    load_config "$FIXTURE_DIR/simple.yml"
    [ "$CFG_BASE_BRANCH" = "main" ]
}

@test "load_config extracts worktree enabled" {
    load_config "$FIXTURE_DIR/django.yml"
    [ "$CFG_WORKTREE_ENABLED" = "true" ]
}

@test "load_config fails on missing file" {
    run load_config "/nonexistent/file.yml"
    [ "$status" -ne 0 ]
}

@test "load_config fails on missing project field" {
    local tmpfile="$TEST_DIR/bad.yml"
    echo "base_branch: main" > "$tmpfile"
    run load_config "$tmpfile"
    [ "$status" -ne 0 ]
}

# ─── find_config ────────────────────────────────────────────────────────────

@test "find_config finds orchestrator.yml in current directory" {
    local project_dir="$TEST_DIR/myproject"
    mkdir -p "$project_dir"
    echo "project: test" > "$project_dir/orchestrator.yml"

    cd "$project_dir"
    result=$(find_config)
    [ "$result" = "$project_dir/orchestrator.yml" ]
}

@test "find_config walks up directories" {
    local project_dir="$TEST_DIR/myproject"
    mkdir -p "$project_dir/src/components"
    echo "project: test" > "$project_dir/orchestrator.yml"

    cd "$project_dir/src/components"
    result=$(find_config)
    [ "$result" = "$project_dir/orchestrator.yml" ]
}

@test "find_config returns error when not found" {
    cd "$TEST_DIR"
    run find_config
    [ "$status" -ne 0 ]
}

# ─── get_port_names ─────────────────────────────────────────────────────────

@test "get_port_names returns port names from config" {
    result=$(get_port_names "$FIXTURE_DIR/django.yml")
    echo "$result" | grep -q "backend"
    echo "$result" | grep -q "frontend"
}

@test "get_port_names returns single port" {
    result=$(get_port_names "$FIXTURE_DIR/simple.yml")
    [ "$(echo "$result" | wc -l | tr -d ' ')" = "1" ]
    echo "$result" | grep -q "backend"
}

# ─── get_port_start ─────────────────────────────────────────────────────────

@test "get_port_start returns configured start port" {
    result=$(get_port_start "$FIXTURE_DIR/django.yml" "backend")
    [ "$result" = "8000" ]
}

@test "get_port_start returns frontend start port" {
    result=$(get_port_start "$FIXTURE_DIR/django.yml" "frontend")
    [ "$result" = "5173" ]
}

# ─── get_window_count ───────────────────────────────────────────────────────

@test "get_window_count returns correct count" {
    result=$(get_window_count "$FIXTURE_DIR/simple.yml")
    [ "$result" = "2" ]
}

@test "get_window_count returns 6 for django fixture" {
    result=$(get_window_count "$FIXTURE_DIR/django.yml")
    [ "$result" = "6" ]
}

# ─── get_window_field ───────────────────────────────────────────────────────

@test "get_window_field returns window name" {
    result=$(get_window_field "$FIXTURE_DIR/simple.yml" 0 "name")
    [ "$result" = 'server:${backend_port}' ]
}

@test "get_window_field returns window command" {
    result=$(get_window_field "$FIXTURE_DIR/simple.yml" 0 "command")
    [ "$result" = 'python -m http.server ${backend_port}' ]
}

@test "get_window_field returns empty for shell window command" {
    result=$(get_window_field "$FIXTURE_DIR/simple.yml" 1 "command")
    [ -z "$result" ]
}

@test "get_window_field returns directory" {
    result=$(get_window_field "$FIXTURE_DIR/django.yml" 1 "directory")
    [ "$result" = "frontend" ]
}

# ─── get_env_substitutions ──────────────────────────────────────────────────

@test "get_env_substitutions returns key=value pairs" {
    result=$(get_env_substitutions "$FIXTURE_DIR/django.yml" "frontend/.env")
    echo "$result" | grep -q 'VITE_API_URL=http://localhost:${backend_port}'
}
