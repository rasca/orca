#!/bin/bash
# ports.sh — Global port allocation across all projects

source "$(dirname "${BASH_SOURCE[0]}")/session.sh"

# Get all used ports for a given port name across all sessions
get_used_ports() {
    local port_name="$1"
    init_sessions
    jq -r ".[].ports.${port_name} // empty" "$SESSIONS_FILE" 2>/dev/null | sort -n
}

# Check if a port is in use on the host (by any process)
port_in_use() {
    local port="$1"
    lsof -iTCP:"$port" -sTCP:LISTEN -P -n > /dev/null 2>&1
}

# Allocate ports for a session based on config
# Uses a shared offset so all ports increment together:
#   offset 0 → backend=8000, frontend=5000
#   offset 1 → backend=8001, frontend=5001
allocate_ports() {
    local config_file="$1"
    local port_names
    port_names=$(get_port_names "$config_file")

    # Collect start ports and used ports for each name
    local names=()
    local starts=()
    local used_lists=()

    for port_name in $port_names; do
        names+=("$port_name")
        starts+=("$(get_port_start "$config_file" "$port_name")")
        used_lists+=("$(get_used_ports "$port_name")")
    done

    # Find smallest offset where ALL ports are free
    local offset=0
    while true; do
        local all_free=true
        for i in "${!names[@]}"; do
            local port=$((starts[i] + offset))
            if echo "${used_lists[$i]}" | grep -q "^${port}$" || port_in_use "$port"; then
                all_free=false
                break
            fi
        done
        if [ "$all_free" = true ]; then
            break
        fi
        offset=$((offset + 1))
    done

    for i in "${!names[@]}"; do
        echo "${names[$i]}_port=$((starts[i] + offset))"
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
