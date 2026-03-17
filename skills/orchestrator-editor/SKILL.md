---
name: orchestrator-editor
description: >
  Understands and edits orchestrator.yml files for the orca Docker session orchestrator.
  Provides full spec knowledge, framework recipes, and validation.
  Use when asked to "edit orchestrator.yml", "add a window", "change ports",
  "modify orca config", "configure orca session", "update orchestrator",
  "add a service", "add a worker", "change the setup", "add volumes",
  "add environment variables", or understand the orchestrator.yml format.
allowed-tools: Read, Write, Edit, Glob, Grep
---

# orchestrator.yml — Editing & Reference Guide

## Overview

`orchestrator.yml` is the configuration file for **orca**, a Docker-isolated development session orchestrator. orca creates sandboxed dev environments where:

- **tmux runs on the host** — preserving the user's tmux config, clipboard, and key bindings
- **Each tmux window runs `docker exec -it` into a shared container** — full isolation with no cross-project interference
- **Git worktrees** provide branch-per-session isolation — each session gets its own working copy
- **Ports are globally allocated** across all projects/sessions to prevent conflicts

The `orchestrator.yml` file lives at the project root and defines everything orca needs: project identity, setup steps, Docker config, port allocation, window layout, and environment variables.

## Full Specification

### Top-Level Fields

```yaml
project: <string>        # Required. Project identifier (e.g., "myapp")
base_branch: <string>    # Required. Branch to create worktrees from (e.g., "main", "dev")
```

### worktree

```yaml
worktree:
  enabled: <boolean>     # Whether to create git worktrees for sessions (default: true)
```

When enabled, `orca add <name>` creates a worktree at `~/Dev/<project>-<name>/`. When disabled, the project directory itself is mounted into Docker.

### setup

```yaml
setup:
  copy:                    # Files to copy from main project to each new worktree
    - <relative-path>      # e.g., "backend/.env", ".claude/settings.local.json"

  env_substitutions:       # After copying, update values in specific files
    "<relative-path>":     # Target file to modify
      <KEY>: "<value>"     # KEY=value line to set/update (supports interpolation)
```

- `copy` entries are relative paths from the project root
- `env_substitutions` targets must be files listed in `copy` (they're modified after copying)
- Values in `env_substitutions` support variable interpolation (see below)

### docker

```yaml
docker:
  python_requirements: <path>   # Path to requirements.txt (relative to project root)
  node_install:                 # Directories where `npm install` should run
    - <relative-path>           # e.g., "frontend", "."
  volumes:                      # Named Docker volumes (bypass macOS bind mount slowness)
    <name>: <container-path>    # e.g., node_modules: /workspace/frontend/node_modules
```

Named volumes are created as `orca-<project>-<session>-<name>` and persist across container restarts. Use them for `node_modules` and virtual environments on macOS to avoid bind mount performance issues.

### ports

```yaml
ports:
  <port_name>: { start: <number> }
```

Each port is auto-allocated starting from `start`. The next available port is found by scanning all active sessions across all projects. Port names become variables via `${<port_name>_port}`.

### windows

```yaml
windows:
  - name: "<display-name>"       # tmux window name (supports interpolation)
    directory: <relative-path>   # Working directory inside /workspace (default: .)
    command: "<shell-command>"   # Command to run (supports interpolation)
    resume_command: "<command>"  # Optional: command for `orca resume` instead of `command`
```

**Command behavior:**
- Non-empty `command`: runs `docker exec -it <container> bash -c 'cd /workspace/<dir> && <command>'`
- Empty `command` (`""`): opens an interactive shell via `docker exec -it <container> bash -l`
- `resume_command`: used by `orca resume` instead of `command` (essential for `claude --resume`)

### env

```yaml
env:
  - <VAR_NAME>    # Environment variable name passed from host to container
```

Variables are passed through from the host environment. If not set on the host, silently skipped.

## Architecture

```
Host tmux session ("orca-<project>-<session>")
  window 0: "backend:8000"  → docker exec -it <container> bash -c 'cd /workspace/backend && python manage.py runserver 0.0.0.0:8000'
  window 1: "frontend:5000" → docker exec -it <container> bash -c 'cd /workspace/frontend && npm run dev -- --port 5000 --host 0.0.0.0'
  window 2: "claude"        → docker exec -it <container> bash -c 'cd /workspace && claude --dangerously-skip-permissions'
  window 3: "shell"         → docker exec -it <container> bash -l
  window 4: "cli"           → docker exec -it <container> bash -l

Container:
  /workspace  ← bind mount of project worktree (rw)
  ~/.gitconfig, ~/.ssh, ~/.config/gh  ← bind mounted (ro)
  SSH agent  ← forwarded
  Named volumes for node_modules, venvs  ← fast I/O
```

Servers inside Docker **must bind to `0.0.0.0`** — not `localhost` or `127.0.0.1` — for port forwarding from the host to work.

## Variable Interpolation

These variables are available in window `name`, `command`, `resume_command`, and `env_substitutions` values:

| Variable | Source | Example |
|----------|--------|---------|
| `${project}` | `project` field | `myapp` |
| `${session}` | session name from `orca add <name>` | `feature-x` |
| `${<port_name>_port}` | allocated port for `<port_name>` in `ports` section | `${backend_port}` → `8000` |

Port variable naming: the port name in the `ports:` section gets `_port` appended. So `ports.backend` → `${backend_port}`, `ports.frontend` → `${frontend_port}`, `ports.app` → `${app_port}`.

## Framework Window Recipes

### Django

```yaml
# Dev server
- name: "backend:${backend_port}"
  directory: backend
  command: "python manage.py runserver 0.0.0.0:${backend_port}"

# Interactive shell (use shell_plus if django-extensions is installed)
- name: django-shell
  directory: backend
  command: "python manage.py shell_plus --ipython"

# Celery worker (if celery is in requirements)
- name: celery
  directory: backend
  command: "celery -A <app_name> worker -l info"

# Celery beat scheduler (if periodic tasks are used)
- name: celery-beat
  directory: backend
  command: "celery -A <app_name> beat -l info"
```

### Flask

```yaml
- name: "app:${app_port}"
  directory: .
  command: "flask run --host 0.0.0.0 --port ${app_port}"
```

### FastAPI

```yaml
- name: "api:${api_port}"
  directory: .
  command: "uvicorn main:app --host 0.0.0.0 --port ${api_port} --reload"
```

### Svelte / Vite

```yaml
- name: "frontend:${frontend_port}"
  directory: frontend
  command: "npm run dev -- --port ${frontend_port} --host 0.0.0.0"
```

### React / Next.js

```yaml
# Next.js — note: --hostname not --host
- name: "frontend:${frontend_port}"
  directory: frontend
  command: "npm run dev -- --port ${frontend_port} --hostname 0.0.0.0"

# Create React App
- name: "frontend:${frontend_port}"
  directory: frontend
  command: "PORT=${frontend_port} HOST=0.0.0.0 npm start"
```

### Vue / Nuxt

```yaml
- name: "frontend:${frontend_port}"
  directory: frontend
  command: "npm run dev -- --port ${frontend_port} --host 0.0.0.0"
```

### Express / Node.js

```yaml
- name: "app:${app_port}"
  directory: .
  command: "PORT=${app_port} npm run dev"
```

Ensure the app code uses `app.listen(port, '0.0.0.0')` — Express defaults to `0.0.0.0` but some setups override this.

### Go

```yaml
- name: "app:${app_port}"
  directory: .
  command: "go run . --port ${app_port}"
```

Or if using a Makefile: `command: "make run PORT=${app_port}"`. Ensure the Go server binds to `0.0.0.0`.

## Standard Windows

Every orchestrator.yml should include these three windows:

```yaml
# Claude Code — with bypass permissions and agent teams
- name: claude
  directory: .
  command: "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude --dangerously-skip-permissions"
  resume_command: "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude --dangerously-skip-permissions --resume"

# Interactive shell for manual work
- name: shell
  directory: .
  command: ""

# CLI window for one-off commands
- name: cli
  directory: .
  command: ""
```

The `claude` window **must** have both `command` and `resume_command` so that `orca resume` can reconnect to an existing Claude session.

## Common Editing Tasks

### Add a window

Add a new entry to the `windows` array. If the window runs a server, also add a port:

```yaml
ports:
  backend: { start: 8000 }
  storybook: { start: 6006 }    # ← new port

windows:
  # ... existing windows ...
  - name: "storybook:${storybook_port}"       # ← new window
    directory: frontend
    command: "npm run storybook -- --port ${storybook_port} --host 0.0.0.0"
```

### Change ports

Update the `start` value in the `ports` section. All `${name_port}` references update automatically at runtime:

```yaml
ports:
  backend: { start: 9000 }     # Changed from 8000
```

### Add named volumes

Add entries to `docker.volumes`. Container paths must be absolute under `/workspace`:

```yaml
docker:
  volumes:
    node_modules: /workspace/node_modules
    backend_venv: /workspace/backend/.venv
```

### Add env substitutions

Add the source file to `setup.copy` (if not already there), then add the substitution:

```yaml
setup:
  copy:
    - frontend/.env
  env_substitutions:
    "frontend/.env":
      VITE_API_URL: "http://localhost:${backend_port}"
      VITE_WS_URL: "ws://localhost:${backend_port}"
```

### Add environment variables

Add variable names to the `env` list:

```yaml
env:
  - ANTHROPIC_API_KEY
  - OPENAI_API_KEY
  - GITHUB_TOKEN
```

### Add workers / background services

Add windows without ports (they don't expose network services):

```yaml
- name: worker
  directory: .
  command: "python manage.py run_worker"

- name: scheduler
  directory: .
  command: "celery -A myapp beat -l info"
```

## Validation Checklist

When editing or reviewing an orchestrator.yml, verify:

- [ ] **Servers bind to `0.0.0.0`** — not `localhost` or `127.0.0.1` — required for Docker port forwarding
- [ ] **`claude` window has `resume_command`** — enables `orca resume` to reconnect
- [ ] **Port variable references match `ports` section** — `${backend_port}` requires `ports.backend`
- [ ] **`env` includes `ANTHROPIC_API_KEY`** — required for Claude Code inside the container
- [ ] **`node_modules` uses named volumes on macOS** — prevents bind mount performance issues
- [ ] **`env_substitutions` targets are in `setup.copy`** — files must be copied before they can be modified
- [ ] **Window names with ports use interpolation** — `"backend:${backend_port}"` not `"backend:8000"`
- [ ] **`project` and `base_branch` are set** — both are required top-level fields
- [ ] **Next.js uses `--hostname`** not `--host` — Next.js CLI differs from Vite/Svelte
- [ ] **Shell/CLI windows have empty command `""`** — not omitted, explicitly empty string
- [ ] **`directory` paths are relative** — relative to project root, mapped under `/workspace`

## Complete Example

A full Django + Svelte project with Celery workers, shell_plus, env substitutions, and named volumes:

```yaml
project: myapp
base_branch: main

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
      VITE_WS_URL: "ws://localhost:${backend_port}"

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
  - name: django-shell
    directory: backend
    command: "python manage.py shell_plus --ipython"
  - name: celery
    directory: backend
    command: "celery -A myapp worker -l info"
  - name: celery-beat
    directory: backend
    command: "celery -A myapp beat -l info"
  - name: claude
    directory: .
    command: "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude --dangerously-skip-permissions"
    resume_command: "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude --dangerously-skip-permissions --resume"
  - name: shell
    directory: .
    command: ""
  - name: cli
    directory: .
    command: ""

env:
  - ANTHROPIC_API_KEY
  - OPENAI_API_KEY
```
