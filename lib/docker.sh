#!/bin/bash
# docker.sh — Docker container lifecycle management

ORCA_DOCKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docker"
ORCA_IMAGE_NAME="orca-base:latest"

# Build the base Docker image
docker_build() {
    local uid
    local gid
    uid=$(id -u)
    gid=$(id -g)

    echo "Building orca base image..."
    docker build \
        --platform linux/arm64 \
        --build-arg DEV_UID="$uid" \
        --build-arg DEV_GID="$gid" \
        --build-arg DEV_USER="$(whoami)" \
        -t "$ORCA_IMAGE_NAME" \
        -f "$ORCA_DOCKER_DIR/Dockerfile" \
        "$ORCA_DOCKER_DIR/"

    if [ $? -eq 0 ]; then
        echo "Image built successfully: $ORCA_IMAGE_NAME"
    else
        echo "Error: Failed to build image" >&2
        return 1
    fi
}

# Start a container for a session
# Args: container_name workspace_path project_root port_pairs... -- env_vars... -- volume_pairs...
docker_start_container() {
    local container_name="$1"
    local workspace_path="$2"
    local project_root="$3"
    shift 3

    local docker_args=()
    docker_args+=(run -d)
    docker_args+=(--name "$container_name")
    docker_args+=(--platform linux/arm64)
    docker_args+=(--hostname "$container_name")

    # Workspace bind mount
    docker_args+=(-v "$workspace_path:/workspace")

    # Mount main repo .git so worktree git operations work inside container
    if [ -n "$project_root" ] && [ "$workspace_path" != "$project_root" ]; then
        docker_args+=(-v "$project_root/.git:$project_root/.git")
    fi

    # Host config mounts (read-only)
    [ -f "$HOME/.gitconfig" ] && docker_args+=(-v "$HOME/.gitconfig:/home/$(whoami)/.gitconfig:ro")
    [ -d "$HOME/.ssh" ] && docker_args+=(-v "$HOME/.ssh:/home/$(whoami)/.ssh:ro")
    # gh CLI config: copied into container after start (not bind-mounted because
    # macOS stores tokens in Keychain, making the config file useless read-only)

    # Claude Code config: copied into container after start (not bind-mounted
    # to avoid read-only errors and corruption from concurrent writes)

    # Claude Code OAuth token (from `claude setup-token`)
    [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && docker_args+=(-e "CLAUDE_CODE_OAUTH_TOKEN")

    # SSH agent forwarding (macOS Docker Desktop)
    if [ -S "/run/host-services/ssh-auth.sock" ] 2>/dev/null || true; then
        docker_args+=(--mount "type=bind,src=/run/host-services/ssh-auth.sock,target=/run/host-services/ssh-auth.sock")
        docker_args+=(-e "SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock")
    fi

    # Parse remaining args: ports -- env_vars -- volumes
    local mode="ports"
    while [ $# -gt 0 ]; do
        if [ "$1" = "--" ]; then
            if [ "$mode" = "ports" ]; then
                mode="env"
            elif [ "$mode" = "env" ]; then
                mode="volumes"
            fi
            shift
            continue
        fi

        case "$mode" in
            ports)
                # port_name_port=number
                local port="${1#*=}"
                docker_args+=(-p "${port}:${port}")
                ;;
            env)
                # ENV_VAR_NAME (pass through from host)
                docker_args+=(-e "$1")
                ;;
            volumes)
                # volume_name=container_path
                local vol_name="${1%%=*}"
                local vol_path="${1#*=}"
                docker_args+=(--volume "${vol_name}:${vol_path}")
                ;;
        esac
        shift
    done

    docker_args+=("$ORCA_IMAGE_NAME")

    echo "Starting container: $container_name"
    docker "${docker_args[@]}"

    if [ $? -eq 0 ]; then
        echo "Container started: $container_name"
    else
        echo "Error: Failed to start container" >&2
        return 1
    fi
}

# Execute a command inside a container (interactive)
docker_exec_it() {
    local container_name="$1"
    shift
    docker exec -it "$container_name" "$@"
}

# Execute a command inside a container (non-interactive)
docker_exec() {
    local container_name="$1"
    shift
    docker exec "$container_name" "$@"
}

# Stop a container
docker_stop_container() {
    local container_name="$1"
    echo "Stopping container: $container_name"
    docker stop "$container_name" 2>/dev/null
}

# Remove a container
docker_rm_container() {
    local container_name="$1"
    echo "Removing container: $container_name"
    docker rm -f "$container_name" 2>/dev/null
}

# Remove a named volume
docker_rm_volume() {
    local volume_name="$1"
    docker volume rm "$volume_name" 2>/dev/null
}

# Check if a container is running
docker_is_running() {
    local container_name="$1"
    local status
    status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null)
    [ "$status" = "running" ]
}

# Check if a container exists (running or stopped)
docker_exists() {
    local container_name="$1"
    docker inspect "$container_name" > /dev/null 2>&1
}

# Get container status
docker_status() {
    local container_name="$1"
    docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null || echo "removed"
}

# Run setup commands inside a container (install deps)
docker_run_setup() {
    local container_name="$1"
    local config_file="$2"

    # Copy Claude Code config into the container (not bind-mounted to avoid
    # read-only errors in ~/.claude/ and corruption from concurrent writes)
    local claude_home="/home/$(whoami)"
    if [ -f "$HOME/.claude.json" ]; then
        docker cp "$HOME/.claude.json" "$container_name:$claude_home/.claude.json"
    fi
    if [ -f "$HOME/.claude/settings.json" ]; then
        docker exec "$container_name" mkdir -p "$claude_home/.claude" 2>/dev/null || true
        docker cp "$HOME/.claude/settings.json" "$container_name:$claude_home/.claude/settings.json"
    fi

    # Set up gh CLI auth (macOS stores tokens in Keychain, so bind-mounting
    # the config doesn't work — extract the real token and inject it)
    if command -v gh &>/dev/null; then
        local gh_token
        gh_token=$(gh auth token 2>/dev/null) || true
        if [ -n "$gh_token" ]; then
            echo "Setting up GitHub CLI auth..."
            docker exec -e _GH_AUTH_TOKEN="$gh_token" "$container_name" \
                bash -c 'echo "$_GH_AUTH_TOKEN" | gh auth login --with-token && gh auth setup-git' 2>/dev/null || true
        fi
    fi

    # Fix ownership of named volume mounts (Docker creates them as root)
    local volumes
    volumes=$(get_docker_volumes "$config_file")
    for vol in $volumes; do
        if [ -n "$vol" ] && [ "$vol" != "null" ]; then
            local vol_path="${vol#*=}"
            docker exec "$container_name" sudo chown "$(id -u):$(id -g)" "$vol_path" 2>/dev/null || true
        fi
    done

    # Python requirements
    local py_req
    py_req=$(get_python_requirements "$config_file")
    if [ -n "$py_req" ]; then
        echo "Installing Python dependencies..."
        docker exec "$container_name" bash -c "cd /workspace && pip install --break-system-packages -r $py_req" || true
    fi

    # Node.js installs
    local node_dirs
    node_dirs=$(get_node_install_dirs "$config_file")
    for dir in $node_dirs; do
        if [ -n "$dir" ] && [ "$dir" != "null" ]; then
            echo "Installing Node.js dependencies in $dir..."
            docker exec "$container_name" bash -c "cd /workspace/$dir && npm install" || true
        fi
    done
}
