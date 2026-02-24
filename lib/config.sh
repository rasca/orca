#!/bin/bash
# config.sh — Parse orchestrator.yml and perform variable interpolation

ORCA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Find orchestrator.yml by walking up from $PWD
find_config() {
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/orchestrator.yml" ]; then
            echo "$dir/orchestrator.yml"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# Get the project root (directory containing orchestrator.yml)
get_project_root() {
    local config
    config=$(find_config) || return 1
    dirname "$config"
}

# Read a value from orchestrator.yml using yq
config_get() {
    local config_file="$1"
    local path="$2"
    yq eval "$path" "$config_file" 2>/dev/null
}

# Read an array from orchestrator.yml, one item per line
config_get_array() {
    local config_file="$1"
    local path="$2"
    yq eval "($path // []) | .[]" "$config_file" 2>/dev/null || true
}

# Count array items
config_count() {
    local config_file="$1"
    local path="$2"
    yq eval "$path | length" "$config_file" 2>/dev/null
}

# Perform variable interpolation on a string
# Replaces ${project}, ${session}, ${<port_name>_port}
interpolate() {
    local template="$1"
    local project="$2"
    local session="$3"
    shift 3
    # remaining args are key=value pairs for ports
    local result="$template"
    result="${result//\$\{project\}/$project}"
    result="${result//\$\{session\}/$session}"

    # Replace port variables from key=value pairs
    while [ $# -gt 0 ]; do
        local key="${1%%=*}"
        local val="${1#*=}"
        result="${result//\$\{${key}\}/$val}"
        shift
    done

    echo "$result"
}

# Load all config into shell variables
# Sets: CFG_PROJECT, CFG_BASE_BRANCH, CFG_WORKTREE_ENABLED, etc.
load_config() {
    local config_file="$1"

    if [ ! -f "$config_file" ]; then
        echo "Error: Config file not found: $config_file" >&2
        return 1
    fi

    CFG_PROJECT=$(config_get "$config_file" '.project')
    CFG_BASE_BRANCH=$(config_get "$config_file" '.base_branch // "main"')
    CFG_WORKTREE_ENABLED=$(config_get "$config_file" '.worktree.enabled // false')

    # Validate required fields
    if [ "$CFG_PROJECT" = "null" ] || [ -z "$CFG_PROJECT" ]; then
        echo "Error: 'project' is required in orchestrator.yml" >&2
        return 1
    fi
}

# Get port names defined in config
get_port_names() {
    local config_file="$1"
    yq eval '.ports | keys | .[]' "$config_file" 2>/dev/null
}

# Get start port for a named port
get_port_start() {
    local config_file="$1"
    local port_name="$2"
    yq eval ".ports.${port_name}.start // 3000" "$config_file" 2>/dev/null
}

# Get window count
get_window_count() {
    local config_file="$1"
    config_count "$config_file" '.windows'
}

# Get window field by index
get_window_field() {
    local config_file="$1"
    local index="$2"
    local field="$3"
    yq eval ".windows[$index].$field // \"\"" "$config_file" 2>/dev/null
}

# Get env vars to pass to container
get_env_vars() {
    local config_file="$1"
    config_get_array "$config_file" '.env'
}

# Get docker volume definitions
get_docker_volumes() {
    local config_file="$1"
    yq eval '(.docker.volumes // {}) | to_entries | .[] | .key + "=" + .value' "$config_file" 2>/dev/null || true
}

# Get python requirements file path
get_python_requirements() {
    local config_file="$1"
    local val
    val=$(config_get "$config_file" '.docker.python_requirements // ""')
    if [ "$val" != "null" ] && [ -n "$val" ]; then
        echo "$val"
    fi
}

# Get node install directories
get_node_install_dirs() {
    local config_file="$1"
    config_get_array "$config_file" '.docker.node_install'
}

# Get setup copy files
get_setup_copy_files() {
    local config_file="$1"
    config_get_array "$config_file" '.setup.copy'
}

# Get env substitutions for a file
get_env_substitutions() {
    local config_file="$1"
    local target_file="$2"
    yq eval ".setup.env_substitutions[\"$target_file\"] | to_entries | .[] | .key + \"=\" + .value" "$config_file" 2>/dev/null
}
