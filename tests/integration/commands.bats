#!/usr/bin/env bats

# Integration tests that mock docker, tmux, and git

ORCA_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    TEST_DIR="$(mktemp -d)"
    export ORCA_STATE_DIR="$TEST_DIR/state"
    export HOME="$TEST_DIR/home"
    mkdir -p "$HOME"

    FIXTURE_DIR="$ORCA_ROOT/tests/fixtures"

    # Create a mock bin directory and prepend to PATH
    MOCK_BIN="$TEST_DIR/mock-bin"
    mkdir -p "$MOCK_BIN"
    export PATH="$MOCK_BIN:$PATH"

    # Record all mock calls
    MOCK_LOG="$TEST_DIR/mock-calls.log"
    export MOCK_LOG
    : > "$MOCK_LOG"

    # ── Mock docker ──
    cat > "$MOCK_BIN/docker" << 'MOCK'
#!/bin/bash
echo "docker $*" >> "$MOCK_LOG"
case "$1" in
    inspect)
        if [[ "$*" == *"--format"*"Status"* ]]; then
            echo "running"
        else
            echo "{}"
        fi
        ;;
    run|start|stop|rm|exec|build)
        echo "mock-container-id"
        ;;
    volume)
        ;;
    info)
        ;;
esac
MOCK
    chmod +x "$MOCK_BIN/docker"

    # ── Mock tmux ──
    cat > "$MOCK_BIN/tmux" << 'MOCK'
#!/bin/bash
echo "tmux $*" >> "$MOCK_LOG"
case "$1" in
    has-session)
        return 1
        ;;
    new-session|new-window|send-keys|kill-session)
        ;;
esac
MOCK
    chmod +x "$MOCK_BIN/tmux"

    # ── Mock git ──
    cat > "$MOCK_BIN/git" << 'MOCK'
#!/bin/bash
echo "git $*" >> "$MOCK_LOG"
case "$1" in
    remote)
        return 1
        ;;
    rev-parse)
        echo "abc123"
        ;;
    branch)
        echo "main"
        ;;
    worktree)
        ;;
    symbolic-ref)
        echo "refs/remotes/origin/main"
        ;;
    fetch|pull|checkout)
        ;;
    show-ref)
        return 1
        ;;
esac
MOCK
    chmod +x "$MOCK_BIN/git"

    # Source all lib files
    source "$ORCA_ROOT/lib/config.sh"
    source "$ORCA_ROOT/lib/session.sh"
    source "$ORCA_ROOT/lib/ports.sh"
    source "$ORCA_ROOT/lib/docker.sh"
    source "$ORCA_ROOT/lib/tmux.sh"
    source "$ORCA_ROOT/lib/git.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ─── orca list ──────────────────────────────────────────────────────────────

@test "list with no sessions shows empty" {
    init_sessions
    # Simulate cmd_list logic: just check session_keys
    result=$(session_keys)
    [ -z "$result" ]
}

@test "list shows existing sessions" {
    session_save "myapp/feat-1" '{"project":"myapp","session_name":"feat-1","container_name":"orca-myapp-feat-1","ports":{"backend":8000}}'
    session_save "myapp/feat-2" '{"project":"myapp","session_name":"feat-2","container_name":"orca-myapp-feat-2","ports":{"backend":8001}}'

    keys=$(session_keys)
    echo "$keys" | grep -q "myapp/feat-1"
    echo "$keys" | grep -q "myapp/feat-2"
}

# ─── orca add (mocked) ─────────────────────────────────────────────────────

@test "add calls docker and tmux in correct order" {
    # Set up a project directory with config
    local project_dir="$TEST_DIR/myproject"
    mkdir -p "$project_dir"
    cp "$FIXTURE_DIR/simple.yml" "$project_dir/orchestrator.yml"
    cd "$project_dir"

    # Simulate the add workflow
    local config_file="$project_dir/orchestrator.yml"
    load_config "$config_file"

    local session_name="feat-1"
    local session_key="$CFG_PROJECT/$session_name"
    local container_name="orca-${CFG_PROJECT}-${session_name}"

    # Allocate ports
    local port_vars=()
    while IFS= read -r line; do
        [ -n "$line" ] && port_vars+=("$line")
    done < <(allocate_ports "$config_file")

    # Start container (mocked)
    docker_start_container "$container_name" "$project_dir" "${port_vars[@]}" "--" "--"

    # Verify docker run was called
    grep -q "docker run" "$MOCK_LOG"

    # Create tmux session (mocked)
    create_tmux_session "${CFG_PROJECT}-${session_name}" "$container_name" "$config_file" \
        "$CFG_PROJECT" "$session_name" "${port_vars[@]}"

    # Verify tmux commands were called
    grep -q "tmux new-session" "$MOCK_LOG"

    # Verify docker was called before tmux new-session
    local docker_line tmux_line
    docker_line=$(grep -n "docker run" "$MOCK_LOG" | head -1 | cut -d: -f1)
    tmux_line=$(grep -n "tmux new-session" "$MOCK_LOG" | head -1 | cut -d: -f1)
    [ "$docker_line" -lt "$tmux_line" ]
}

# ─── orca remove (mocked) ──────────────────────────────────────────────────

@test "remove cleans up session state" {
    # Create a session first
    session_save "myapp/feat-1" '{"project":"myapp","session_name":"feat-1","container_name":"orca-myapp-feat-1","ports":{"backend":8000},"volumes":{},"worktree_path":"/tmp/test","project_root":"/tmp/test","branch":""}'

    session_exists "myapp/feat-1"

    # Remove it
    local container_name
    container_name=$(session_get_field "myapp/feat-1" "container_name")
    [ "$container_name" = "orca-myapp-feat-1" ]

    kill_tmux_session "myapp-feat-1"
    docker_rm_container "$container_name"
    session_remove "myapp/feat-1"

    run session_exists "myapp/feat-1"
    [ "$status" -ne 0 ]
}

# ─── orca add with missing config ──────────────────────────────────────────

@test "find_config fails when no config exists" {
    cd "$TEST_DIR"
    run find_config
    [ "$status" -ne 0 ]
}
