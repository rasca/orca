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

### `init` — Analyze Project and Generate orchestrator.yml

When the user says `/orca init` or asks to set up orca for a project, perform a **deep analysis** of the project to generate an optimal `orchestrator.yml`.

#### Step 1: Explore the Project

Read and analyze these files (skip any that don't exist):

- **Directory structure**: Use Glob to understand the layout (`*`, `*/`, `**/*.py`, `**/*.ts`)
- **package.json**: Check `scripts`, `dependencies`, `devDependencies` — identify frameworks (svelte, react, next, vue, vite, express, nestjs, etc.)
- **requirements.txt / pyproject.toml / Pipfile**: Identify Python frameworks and tools
- **manage.py / backend/manage.py**: Django detection. Check `INSTALLED_APPS` in settings for django-extensions (shell_plus), celery, rest_framework, etc.
- **docker-compose.yml**: Understand what services normally run (redis, postgres, workers, etc.)
- **Makefile**: Look for development targets (run, dev, serve, test, migrate, etc.)
- **.env / backend/.env / frontend/.env**: Identify environment variables, especially API URLs
- **Procfile**: Process definitions if present
- **README.md**: Often describes how to run the project

#### Step 2: Determine Windows

Each window should match a real development need. Pick from these patterns based on what you discover:

**Django projects:**
- `backend:${backend_port}` — `python manage.py runserver 0.0.0.0:${backend_port}`
- `django-shell` — `python manage.py shell_plus --ipython` (if django-extensions is installed) or `python manage.py shell`
- `celery` — `celery -A <app> worker -l info` (if celery is in requirements)
- `celery-beat` — `celery -A <app> beat -l info` (if celery-beat is used)

**Flask/FastAPI projects:**
- `backend:${backend_port}` — `flask run --host 0.0.0.0 --port ${backend_port}` or `uvicorn main:app --host 0.0.0.0 --port ${backend_port} --reload`

**Svelte projects:**
- `frontend:${frontend_port}` — `npm run dev -- --port ${frontend_port} --host 0.0.0.0`

**React/Next.js projects:**
- `frontend:${frontend_port}` — `npm run dev -- --port ${frontend_port} --hostname 0.0.0.0`
- For Next.js: check if there's a custom server

**Vue/Nuxt projects:**
- `frontend:${frontend_port}` — `npm run dev -- --port ${frontend_port} --host 0.0.0.0`

**Express/Node.js backend:**
- `app:${app_port}` — check package.json scripts for the right dev command (often `npm run dev` or `nodemon`)

**Go projects:**
- `app:${app_port}` — `go run . --port ${app_port}` or check Makefile

**Workers/Background processes:**
- If docker-compose has worker services, add windows for them
- Redis, queue workers, scheduled tasks

**Always include:**
- `claude` — `claude ${project}-${session}` with `resume_command: claude ${project}-${session} --resume`
- `shell` — empty command (interactive shell)
- `cli` — empty command (for one-off commands)

#### Step 3: Determine Setup

- **copy**: List all .env files, SQLite databases (db.sqlite3), Claude settings (.claude/settings.local.json) that exist
- **env_substitutions**: If a frontend .env has a variable pointing to the backend URL (VITE_API_URL, NEXT_PUBLIC_API_URL, REACT_APP_API_URL, etc.), add a substitution with `${backend_port}`
- **docker.volumes**: Add named volumes for every `node_modules` directory to avoid macOS bind mount slowness
- **docker.python_requirements**: Point to the requirements file
- **docker.node_install**: List directories that need `npm install`

#### Step 4: Determine Configuration

- **project**: Use the directory name (basename of PWD)
- **base_branch**: Check `git symbolic-ref refs/remotes/origin/HEAD` or fall back to current branch
- **ports**: Assign appropriate start ports (backend: 8000, frontend: 5000, app: 3000, api: 4000, etc.)
- **env**: Always include `ANTHROPIC_API_KEY`. Add others found in .env files that look like API keys or tokens

#### Step 5: Write the File

Read the full spec from [references/orchestrator-yml-spec.md](references/orchestrator-yml-spec.md), then write `orchestrator.yml` to the project root.

#### Critical Rules

- Servers MUST bind to `0.0.0.0` (not localhost/127.0.0.1) for Docker port forwarding
- Use `${project}`, `${session}`, `${port_name_port}` variable interpolation in window names and commands
- Port names in the `ports:` section become `${name_port}` variables (e.g., `ports.backend` -> `${backend_port}`)
- The claude window MUST have both `command` and `resume_command`
- Windows with empty command `""` get an interactive bash shell
- Check if django-extensions is installed before suggesting `shell_plus`
- Verify package.json has the scripts you reference (don't assume `npm run dev` exists)

After writing, briefly explain what was generated and why each window was included.

### No Arguments — Session Context

When invoked as just `/orca` with no arguments:

1. Run `orca list` to show all active sessions
2. Check if the current working directory is inside a session worktree
3. Display the current session context

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
