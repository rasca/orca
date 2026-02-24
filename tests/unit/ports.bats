#!/usr/bin/env bats

setup() {
    load '../setup'
    setup
}

teardown() {
    teardown
}

# ─── allocate_ports ─────────────────────────────────────────────────────────

@test "allocate_ports returns start ports when no sessions exist" {
    init_sessions
    result=$(allocate_ports "$FIXTURE_DIR/simple.yml")
    echo "$result" | grep -q "backend_port=8000"
}

@test "allocate_ports returns start ports for multi-port config" {
    init_sessions
    result=$(allocate_ports "$FIXTURE_DIR/django.yml")
    echo "$result" | grep -q "backend_port=8000"
    echo "$result" | grep -q "frontend_port=5173"
}

@test "allocate_ports increments past used ports" {
    # Save a session that uses port 8000
    session_save "existing/s1" '{"project":"existing","ports":{"backend":8000}}'

    result=$(allocate_ports "$FIXTURE_DIR/simple.yml")
    echo "$result" | grep -q "backend_port=8001"
}

@test "allocate_ports handles multiple port names independently" {
    # Backend 8000 used, frontend 5173 free
    session_save "existing/s1" '{"project":"existing","ports":{"backend":8000}}'

    result=$(allocate_ports "$FIXTURE_DIR/django.yml")
    echo "$result" | grep -q "backend_port=8001"
    echo "$result" | grep -q "frontend_port=5173"
}

@test "allocate_ports skips multiple used ports" {
    session_save "a/s1" '{"project":"a","ports":{"backend":8000}}'
    session_save "b/s2" '{"project":"b","ports":{"backend":8001}}'
    session_save "c/s3" '{"project":"c","ports":{"backend":8002}}'

    result=$(allocate_ports "$FIXTURE_DIR/simple.yml")
    echo "$result" | grep -q "backend_port=8003"
}

@test "allocate_ports skips ports in use on the host" {
    init_sessions
    # Override lsof mock to report port 8000 as in use
    cat > "$MOCK_BIN/lsof" << 'MOCK'
#!/bin/bash
# Simulate port 8000 being in use by another process
for arg in "$@"; do
    if [[ "$arg" == *":8000" ]]; then
        exit 0
    fi
done
exit 1
MOCK
    chmod +x "$MOCK_BIN/lsof"

    result=$(allocate_ports "$FIXTURE_DIR/simple.yml")
    echo "$result" | grep -q "backend_port=8001"
}

@test "allocate_ports skips ports used in sessions AND on host" {
    # Port 8000 used in sessions, port 8001 used on host
    session_save "a/s1" '{"project":"a","ports":{"backend":8000}}'

    cat > "$MOCK_BIN/lsof" << 'MOCK'
#!/bin/bash
for arg in "$@"; do
    if [[ "$arg" == *":8001" ]]; then
        exit 0
    fi
done
exit 1
MOCK
    chmod +x "$MOCK_BIN/lsof"

    result=$(allocate_ports "$FIXTURE_DIR/simple.yml")
    echo "$result" | grep -q "backend_port=8002"
}

# ─── ports_to_json ──────────────────────────────────────────────────────────

@test "ports_to_json builds correct JSON for single port" {
    result=$(ports_to_json "backend_port=8000")
    expected='{"backend":8000}'
    [ "$result" = "$expected" ]
}

@test "ports_to_json builds correct JSON for multiple ports" {
    result=$(ports_to_json "backend_port=8000" "frontend_port=5173")
    # Verify via jq since order might vary in theory
    backend=$(echo "$result" | jq '.backend')
    frontend=$(echo "$result" | jq '.frontend')
    [ "$backend" = "8000" ]
    [ "$frontend" = "5173" ]
}

# ─── get_used_ports ─────────────────────────────────────────────────────────

@test "get_used_ports reads from sessions.json" {
    session_save "a/s1" '{"project":"a","ports":{"backend":8000}}'
    session_save "b/s2" '{"project":"b","ports":{"backend":8001}}'

    result=$(get_used_ports "backend")
    echo "$result" | grep -q "8000"
    echo "$result" | grep -q "8001"
}

@test "get_used_ports returns empty when no sessions" {
    init_sessions
    result=$(get_used_ports "backend")
    [ -z "$result" ]
}

@test "get_used_ports only returns ports for the given name" {
    session_save "a/s1" '{"project":"a","ports":{"backend":8000,"frontend":5173}}'

    backend_result=$(get_used_ports "backend")
    frontend_result=$(get_used_ports "frontend")

    echo "$backend_result" | grep -q "8000"
    ! echo "$backend_result" | grep -q "5173"

    echo "$frontend_result" | grep -q "5173"
    ! echo "$frontend_result" | grep -q "8000"
}
