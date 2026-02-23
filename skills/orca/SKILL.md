---
name: orca
description: >
  This skill should be used when the user asks to "create a session",
  "add a worktree", "manage docker sessions", "set up orca",
  "generate orchestrator.yml", "analyze project for orca config",
  "list sessions", "attach to session", "stop session", "remove session",
  "create PR session", or mentions orca, docker session, or sandboxed development.
allowed-tools: Read, Write, Bash, Glob, Grep
---

# orca — Docker-Isolated Development Session Orchestrator

orca creates Docker-sandboxed development sessions with tmux, git worktrees, and automatic port management. tmux runs on the host; each window executes inside a Docker container via `docker exec`.

## Commands

When the user provides arguments, execute the corresponding orca command:

### Direct CLI Commands

For `add`, `pr`, `update-pr`, `attach`, `stop`, `resume`, `remove`, `list`, `build`:

```bash
orca $ARGUMENTS
```

Execute the command via Bash and display the output.

### `init` — Generate orchestrator.yml

When the user says `/orca init` or asks to set up orca for a project:

1. Read project files to detect the stack:
   - `package.json` → Node.js (check for svelte, react, next, vite)
   - `requirements.txt`, `pyproject.toml`, `setup.py` → Python
   - `manage.py` or `backend/manage.py` → Django
   - `docker-compose.yml` → existing Docker setup
   - `Makefile` → build commands
   - `.env` files → environment variables to copy

2. Read the orchestrator.yml specification from [references/orchestrator-yml-spec.md](references/orchestrator-yml-spec.md)

3. Generate a complete `orchestrator.yml` tailored to the project:
   - Set correct project name and base branch
   - Configure appropriate ports for the detected stack
   - Set up windows with the right commands for each service
   - Include setup.copy for .env files and databases
   - Add env_substitutions for port-dependent config values
   - Configure docker.volumes for node_modules if applicable

4. Write the file and explain what was generated

### No Arguments — Session Context

When invoked as just `/orca` with no arguments:

1. Run `orca list` to show all active sessions
2. Check if the current working directory is inside a session worktree
3. Display the current session context:
   - Project name and session name
   - Container status
   - Allocated ports and URLs
   - Worktree path
   - Other active sessions for the same project

## Architecture Reference

```
Host tmux session
  └─ Each window → docker exec -it <container> bash -c '<command>'

Volume mounts:
  - Project worktree → /workspace (rw)
  - ~/.gitconfig → ro
  - ~/.ssh → ro
  - ~/.config/gh → ro
  - SSH agent → forwarded
```

Servers inside Docker must bind to `0.0.0.0` (not localhost) for port forwarding.

## Prerequisites

- Docker Desktop installed and running
- `yq` installed (`brew install yq`)
- Base image built (`orca build`)
- `orca` binary in PATH (symlink ~/Dev/orchestrator/bin/orca)
