#!/bin/bash
# ports.sh — Global port allocation across all projects

source "$(dirname "${BASH_SOURCE[0]}")/session.sh"

# Get all used ports for a given port name across all sessions
get_used_ports() {
    local port_name="$1"
    init_sessions
    jq -r ".[].ports.${port_name} // empty" "$SESSIONS_FILE" 2>/dev/null | sort -n
}

# Allocate ports for a session based on config
# Outputs key=value pairs: backend_port=8000 frontend_port=5000
allocate_ports() {
    local config_file="$1"
    local port_names
    port_names=$(get_port_names "$config_file")

    for port_name in $port_names; do
        local start
        start=$(get_port_start "$config_file" "$port_name")

        local used
        used=$(get_used_ports "$port_name")

        local port=$start
        while echo "$used" | grep -q "^${port}$"; do
            port=$((port + 1))
        done

        echo "${port_name}_port=$port"
    done
}

# Build a JSON object of port allocations from key=value pairs
ports_to_json() {
    local json="{"
    local first=true
    while [ $# -gt 0 ]; do
        local pair="$1"
        local name="${pair%%_port=*}"
        local port="${pair#*=}"
        if [ "$first" = true ]; then
            first=false
        else
            json+=","
        fi
        json+="\"$name\":$port"
        shift
    done
    json+="}"
    echo "$json"
}
