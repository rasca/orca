#!/usr/bin/env bats

setup() {
    load '../setup'
    setup
}

teardown() {
    teardown
}

# ─── init_sessions ──────────────────────────────────────────────────────────

@test "init_sessions creates state directory" {
    init_sessions
    [ -d "$ORCA_STATE_DIR" ]
}

@test "init_sessions creates empty JSON file" {
    init_sessions
    [ -f "$SESSIONS_FILE" ]
    result=$(cat "$SESSIONS_FILE")
    [ "$result" = "{}" ]
}

@test "init_sessions does not overwrite existing sessions file" {
    mkdir -p "$ORCA_STATE_DIR"
    echo '{"test/session": {"project": "test"}}' > "$SESSIONS_FILE"
    init_sessions
    result=$(jq -r '.["test/session"].project' "$SESSIONS_FILE")
    [ "$result" = "test" ]
}

@test "init_sessions migrates from old location" {
    # Set up old state location
    local old_state_dir="$ORCA_ROOT/state"
    mkdir -p "$old_state_dir"
    echo '{"migrated/session": {"project": "migrated"}}' > "$old_state_dir/sessions.json"

    init_sessions

    # Verify migration happened
    result=$(jq -r '.["migrated/session"].project' "$SESSIONS_FILE")
    [ "$result" = "migrated" ]

    # Clean up old state
    rm -rf "$old_state_dir"
}

@test "init_sessions does not migrate if new state already exists" {
    # Set up old state
    local old_state_dir="$ORCA_ROOT/state"
    mkdir -p "$old_state_dir"
    echo '{"old/session": {"project": "old"}}' > "$old_state_dir/sessions.json"

    # Set up new state
    mkdir -p "$ORCA_STATE_DIR"
    echo '{"new/session": {"project": "new"}}' > "$SESSIONS_FILE"

    init_sessions

    # New state should be preserved
    result=$(jq -r '.["new/session"].project' "$SESSIONS_FILE")
    [ "$result" = "new" ]

    # Old data should NOT be present
    result=$(jq -r '.["old/session"] // "absent"' "$SESSIONS_FILE")
    [ "$result" = "absent" ]

    # Clean up old state
    rm -rf "$old_state_dir"
}

# ─── session_save + session_get ─────────────────────────────────────────────

@test "session_save and session_get roundtrip" {
    local json='{"project":"test","session_name":"feat-1","container_name":"orca-test-feat-1"}'
    session_save "test/feat-1" "$json"
    result=$(session_get "test/feat-1")
    project=$(echo "$result" | jq -r '.project')
    [ "$project" = "test" ]
}

@test "session_get returns empty for missing session" {
    init_sessions
    result=$(session_get "nonexistent/session")
    [ -z "$result" ]
}

# ─── session_exists ─────────────────────────────────────────────────────────

@test "session_exists returns true for existing session" {
    local json='{"project":"test"}'
    session_save "test/feat" "$json"
    session_exists "test/feat"
}

@test "session_exists returns false for missing session" {
    init_sessions
    run session_exists "nonexistent/session"
    [ "$status" -ne 0 ]
}

# ─── session_remove ─────────────────────────────────────────────────────────

@test "session_remove deletes entry" {
    local json='{"project":"test"}'
    session_save "test/feat" "$json"
    session_remove "test/feat"
    run session_exists "test/feat"
    [ "$status" -ne 0 ]
}

# ─── session_keys ───────────────────────────────────────────────────────────

@test "session_keys lists all keys" {
    session_save "proj-a/s1" '{"project":"proj-a"}'
    session_save "proj-b/s2" '{"project":"proj-b"}'
    result=$(session_keys)
    echo "$result" | grep -q "proj-a/s1"
    echo "$result" | grep -q "proj-b/s2"
}

@test "session_keys returns empty for no sessions" {
    init_sessions
    result=$(session_keys)
    [ -z "$result" ]
}

# ─── session_keys_for_project ───────────────────────────────────────────────

@test "session_keys_for_project filters by project" {
    session_save "proj-a/s1" '{"project":"proj-a","session_name":"s1"}'
    session_save "proj-a/s2" '{"project":"proj-a","session_name":"s2"}'
    session_save "proj-b/s3" '{"project":"proj-b","session_name":"s3"}'

    result=$(session_keys_for_project "proj-a")
    echo "$result" | grep -q "proj-a/s1"
    echo "$result" | grep -q "proj-a/s2"
    ! echo "$result" | grep -q "proj-b/s3"
}

# ─── session_get_field ──────────────────────────────────────────────────────

@test "session_get_field extracts nested fields" {
    local json='{"project":"test","ports":{"backend":8000,"frontend":5173}}'
    session_save "test/feat" "$json"
    result=$(session_get_field "test/feat" "ports.backend")
    [ "$result" = "8000" ]
}

@test "session_get_field returns empty for missing field" {
    local json='{"project":"test"}'
    session_save "test/feat" "$json"
    result=$(session_get_field "test/feat" "nonexistent")
    [ -z "$result" ]
}

# ─── Multiple sessions don't clobber ────────────────────────────────────────

@test "multiple sessions don't clobber each other" {
    session_save "proj/s1" '{"project":"proj","session_name":"s1","ports":{"backend":8000}}'
    session_save "proj/s2" '{"project":"proj","session_name":"s2","ports":{"backend":8001}}'

    r1=$(session_get_field "proj/s1" "ports.backend")
    r2=$(session_get_field "proj/s2" "ports.backend")
    [ "$r1" = "8000" ]
    [ "$r2" = "8001" ]
}
