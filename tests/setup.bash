#!/bin/bash
# Common test helpers for BATS tests

# Resolve ORCA_ROOT from this file's location
ORCA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ORCA_ROOT

FIXTURE_DIR="$ORCA_ROOT/tests/fixtures"
export FIXTURE_DIR

setup() {
    TEST_DIR="$(mktemp -d)"
    export ORCA_STATE_DIR="$TEST_DIR/state"
    export HOME="$TEST_DIR/home"
    mkdir -p "$HOME"

    # Mock lsof so port_in_use always returns false in tests
    # Individual tests can override this by prepending to PATH
    MOCK_BIN="$TEST_DIR/mock-bin"
    mkdir -p "$MOCK_BIN"
    cat > "$MOCK_BIN/lsof" << 'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_BIN/lsof"
    export PATH="$MOCK_BIN:$PATH"

    # Source lib files (order matters: config first, then session, then ports)
    source "$ORCA_ROOT/lib/config.sh"
    source "$ORCA_ROOT/lib/session.sh"
    source "$ORCA_ROOT/lib/ports.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}
