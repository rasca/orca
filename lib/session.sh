#!/bin/bash
# session.sh — Session state CRUD using sessions.json

ORCA_STATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/state"
SESSIONS_FILE="$ORCA_STATE_DIR/sessions.json"

# Ensure state directory and sessions file exist
init_sessions() {
    mkdir -p "$ORCA_STATE_DIR"
    if [ ! -f "$SESSIONS_FILE" ]; then
        echo "{}" > "$SESSIONS_FILE"
    fi
}

# Get a session by key (project/session_name)
session_get() {
    local key="$1"
    init_sessions
    jq -r ".[\"$key\"] // empty" "$SESSIONS_FILE"
}

# Check if a session exists
session_exists() {
    local key="$1"
    init_sessions
    jq -e ".[\"$key\"]" "$SESSIONS_FILE" > /dev/null 2>&1
}

# Save a session
session_save() {
    local key="$1"
    local json_data="$2"
    init_sessions

    local tmp
    tmp=$(mktemp)
    jq --arg key "$key" --argjson data "$json_data" '.[$key] = $data' "$SESSIONS_FILE" > "$tmp" \
        && mv "$tmp" "$SESSIONS_FILE"
}

# Remove a session
session_remove() {
    local key="$1"
    init_sessions

    local tmp
    tmp=$(mktemp)
    jq --arg key "$key" 'del(.[$key])' "$SESSIONS_FILE" > "$tmp" \
        && mv "$tmp" "$SESSIONS_FILE"
}

# List all sessions (outputs JSON)
session_list_all() {
    init_sessions
    cat "$SESSIONS_FILE"
}

# List session keys
session_keys() {
    init_sessions
    jq -r 'keys[]' "$SESSIONS_FILE"
}

# List sessions for a specific project
session_keys_for_project() {
    local project="$1"
    init_sessions
    jq -r --arg p "$project" 'to_entries[] | select(.value.project == $p) | .key' "$SESSIONS_FILE"
}

# Get a specific field from a session
session_get_field() {
    local key="$1"
    local field="$2"
    init_sessions
    jq -r ".[\"$key\"].$field // empty" "$SESSIONS_FILE"
}
