#compdef orca

# orca — Zsh completion
# Source this file or symlink into your fpath:
#   fpath=(~/.zfunc $fpath) && autoload -Uz compinit && compinit
#   ln -s /path/to/orca/completions/orca.zsh ~/.zfunc/_orca

_orca_sessions() {
    local sessions_file="${ORCA_STATE_DIR:-$HOME/.orca}/sessions.json"
    [ -f "$sessions_file" ] || return

    # Find current project from orchestrator.yml
    local dir="$PWD" project=""
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/orchestrator.yml" ]; then
            project=$(yq eval '.project' "$dir/orchestrator.yml" 2>/dev/null)
            break
        fi
        dir="$(dirname "$dir")"
    done
    [ -z "$project" ] && return

    local -a names
    names=(${(f)"$(jq -r --arg p "$project" 'to_entries[] | select(.value.project == $p) | .value.session_name' "$sessions_file" 2>/dev/null)"})
    compadd -a names
}

_orca() {
    local -a commands=(
        'build:Build/rebuild the base Docker image'
        'add:Create session (worktree + container + tmux)'
        'pr:Create session from a GitHub PR'
        'update-pr:Update PR session with latest changes'
        'attach:Attach to session tmux'
        'stop:Stop container (preserves worktree + volumes)'
        'resume:Restart stopped session(s)'
        'remove:Remove everything (container, volumes, worktree, branch)'
        'list:List all active sessions'
        'init:Create orchestrator.yml for current project'
        'help:Show help'
    )

    if (( CURRENT == 2 )); then
        _describe -t commands 'orca command' commands
    elif (( CURRENT == 3 )); then
        case "${words[2]}" in
            attach|stop|remove|rm)
                _orca_sessions
                ;;
            resume)
                _orca_sessions
                ;;
            pr|update-pr)
                _message 'PR number'
                ;;
            add)
                _message 'session name'
                ;;
        esac
    fi
}

_orca "$@"
