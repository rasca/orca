# orchestrator.yml Specification

## Top-Level Fields

```yaml
project: <string>          # Required. Project identifier (e.g., "tally", "myapp")
base_branch: <string>      # Required. Branch to create worktrees from (e.g., "main", "dev")
```

## worktree

```yaml
worktree:
  enabled: <boolean>       # Whether to create git worktrees for sessions (default: true)
```

When enabled, `orca add <name>` creates a worktree at `~/Dev/<project>-<name>/`.
When disabled, the project directory itself is mounted into Docker.

## setup

```yaml
setup:
  copy:                    # Files to copy from main project to each new worktree
    - <relative-path>      # e.g., "backend/.env", ".claude/settings.local.json"

  env_substitutions:       # After copying, update values in specific files
    "<relative-path>":     # Target file to modify
      <KEY>: "<value>"     # KEY=value line to set/update
                           # Supports ${port_name_port} interpolation
```

### Variable Interpolation in Values

These variables are available in env_substitutions values:
- `${project}` — project name from config
- `${session}` — session name (e.g., "feature-x")
- `${<port_name>_port}` — allocated port (e.g., `${backend_port}`, `${frontend_port}`)

## docker

```yaml
docker:
  python_requirements: <path>  # Path to requirements.txt (relative to project root)
  node_install:                # Directories where `npm install` should run
    - <relative-path>          # e.g., "frontend", "."
  volumes:                     # Named Docker volumes (fast, bypass macOS bind mount)
    <name>: <container-path>   # e.g., node_modules: /workspace/frontend/node_modules
```

Named volumes are created as `orca-<project>-<session>-<name>` and persist across container restarts. Use them for `node_modules` and virtual environments to avoid macOS bind mount performance issues.

## ports

```yaml
ports:
  <port_name>: { start: <number> }  # Port names are arbitrary identifiers
```

Each port is auto-allocated starting from `start`. The next available port is found by scanning all active sessions across all projects. Port variables become available as `${<port_name>_port}` for interpolation.

Common patterns:
- `backend: { start: 8000 }` → `${backend_port}` = 8000, 8001, 8002...
- `frontend: { start: 5000 }` → `${frontend_port}` = 5000, 5001, 5002...
- `app: { start: 3000 }` → `${app_port}` = 3000, 3001, 3002...

## windows

```yaml
windows:
  - name: "<display-name>"         # tmux window name (supports interpolation)
    directory: <relative-path>     # Working directory inside /workspace
    command: "<shell-command>"     # Command to run (supports interpolation)
    resume_command: "<command>"    # Optional: command to use when resuming a session
```

### Window Command Behavior

- If `command` is non-empty: runs `docker exec -it <container> bash -c 'cd /workspace/<dir> && <command>'`
- If `command` is empty (`""`): opens an interactive shell `docker exec -it <container> bash -l`
- `resume_command` is used by `orca resume` instead of `command` (useful for `claude --resume`)

### Important: Server Binding

Commands that start servers must bind to `0.0.0.0`, not `localhost` or `127.0.0.1`:
- Django: `python manage.py runserver 0.0.0.0:${backend_port}`
- Vite/Svelte: `npm run dev -- --port ${frontend_port} --host 0.0.0.0`
- Next.js: `npm run dev -- --port ${frontend_port} --hostname 0.0.0.0`
- Express: ensure `app.listen(port, '0.0.0.0')`

## env

```yaml
env:
  - <VAR_NAME>           # Environment variable passed from host to container
```

Variables are passed through from the host environment. If the variable isn't set on the host, it's silently skipped.

Common variables:
- `ANTHROPIC_API_KEY` — required for Claude Code inside Docker
- `OPENAI_API_KEY`, `GITHUB_TOKEN`, etc.

## Complete Example

```yaml
project: tally
base_branch: dev

worktree:
  enabled: true

setup:
  copy:
    - backend/.env
    - frontend/.env
    - backend/db.sqlite3
    - .claude/settings.local.json
  env_substitutions:
    "frontend/.env":
      VITE_API_URL: "http://localhost:${backend_port}"

docker:
  python_requirements: backend/requirements.txt
  node_install: [frontend]
  volumes:
    node_modules: /workspace/frontend/node_modules

ports:
  backend: { start: 8000 }
  frontend: { start: 5000 }

windows:
  - name: "backend:${backend_port}"
    directory: backend
    command: "python manage.py runserver 0.0.0.0:${backend_port}"
  - name: "frontend:${frontend_port}"
    directory: frontend
    command: "npm run dev -- --port ${frontend_port} --host 0.0.0.0"
  - name: claude
    directory: .
    command: "claude ${project}-${session}"
    resume_command: "claude ${project}-${session} --resume"
  - name: shell
    directory: .
    command: ""
  - name: cli
    directory: .
    command: ""

env:
  - ANTHROPIC_API_KEY
```
