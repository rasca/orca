#!/bin/bash
# tmux.sh — Create host tmux sessions with docker exec windows

# Create a tmux session on the host with windows that docker exec into a container
# Each window runs its command inside the container
create_tmux_session() {
    local tmux_session_name="$1"
    local container_name="$2"
    local config_file="$3"
    local project="$4"
    local session="$5"
    shift 5
    # remaining args are port key=value pairs for interpolation
    local port_vars=("$@")

    local window_count
    window_count=$(get_window_count "$config_file")

    if [ "$window_count" = "0" ] || [ "$window_count" = "null" ]; then
        echo "Warning: No windows defined in config" >&2
        return 1
    fi

    local first_window=true
    for i in $(seq 0 $((window_count - 1))); do
        local name directory command
        name=$(get_window_field "$config_file" "$i" "name")
        directory=$(get_window_field "$config_file" "$i" "directory")
        command=$(get_window_field "$config_file" "$i" "command")

        # Interpolate variables
        name=$(interpolate "$name" "$project" "$session" "${port_vars[@]}")
        directory=$(interpolate "$directory" "$project" "$session" "${port_vars[@]}")
        command=$(interpolate "$command" "$project" "$session" "${port_vars[@]}")

        # Build the docker exec command for this window
        local docker_cmd
        if [ -n "$command" ] && [ "$command" != "null" ]; then
            docker_cmd="docker exec -it $container_name bash -c 'cd /workspace/$directory && $command'"
        else
            docker_cmd="docker exec -it $container_name bash -l -c 'cd /workspace/$directory && exec bash -l'"
        fi

        if [ "$first_window" = true ]; then
            # Create the session with the first window
            tmux new-session -d -s "$tmux_session_name" -n "$name"
            tmux send-keys -t "$tmux_session_name:$name" "$docker_cmd" C-m
            first_window=false
        else
            # Add subsequent windows
            tmux new-window -t "$tmux_session_name" -n "$name"
            tmux send-keys -t "$tmux_session_name:$name" "$docker_cmd" C-m
        fi
    done
}

# Create a tmux session using resume commands where available
create_tmux_session_resume() {
    local tmux_session_name="$1"
    local container_name="$2"
    local config_file="$3"
    local project="$4"
    local session="$5"
    shift 5
    local port_vars=("$@")

    local window_count
    window_count=$(get_window_count "$config_file")

    if [ "$window_count" = "0" ] || [ "$window_count" = "null" ]; then
        echo "Warning: No windows defined in config" >&2
        return 1
    fi

    local first_window=true
    for i in $(seq 0 $((window_count - 1))); do
        local name directory command resume_command
        name=$(get_window_field "$config_file" "$i" "name")
        directory=$(get_window_field "$config_file" "$i" "directory")
        command=$(get_window_field "$config_file" "$i" "command")
        resume_command=$(get_window_field "$config_file" "$i" "resume_command")

        # Use resume_command if available, otherwise fall back to command
        if [ -n "$resume_command" ] && [ "$resume_command" != "null" ]; then
            command="$resume_command"
        fi

        # Interpolate variables
        name=$(interpolate "$name" "$project" "$session" "${port_vars[@]}")
        directory=$(interpolate "$directory" "$project" "$session" "${port_vars[@]}")
        command=$(interpolate "$command" "$project" "$session" "${port_vars[@]}")

        local docker_cmd
        if [ -n "$command" ] && [ "$command" != "null" ]; then
            docker_cmd="docker exec -it $container_name bash -c 'cd /workspace/$directory && $command'"
        else
            docker_cmd="docker exec -it $container_name bash -l -c 'cd /workspace/$directory && exec bash -l'"
        fi

        if [ "$first_window" = true ]; then
            tmux new-session -d -s "$tmux_session_name" -n "$name"
            tmux send-keys -t "$tmux_session_name:$name" "$docker_cmd" C-m
            first_window=false
        else
            tmux new-window -t "$tmux_session_name" -n "$name"
            tmux send-keys -t "$tmux_session_name:$name" "$docker_cmd" C-m
        fi
    done
}

# Kill a tmux session
kill_tmux_session() {
    local tmux_session_name="$1"
    if tmux has-session -t "$tmux_session_name" 2>/dev/null; then
        echo "Killing tmux session: $tmux_session_name"
        tmux kill-session -t "$tmux_session_name"
    fi
}

# Check if a tmux session exists
tmux_session_exists() {
    local tmux_session_name="$1"
    tmux has-session -t "$tmux_session_name" 2>/dev/null
}
