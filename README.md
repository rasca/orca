# orca

Docker-isolated development session orchestrator. Create sandboxed dev environments with tmux, git worktrees, and automatic port management.

## Why

Running AI coding assistants (like Claude Code) on your host machine is risky — a misguided `rm -rf /` can destroy your system. orca runs everything inside Docker containers while keeping your familiar tmux workflow on the host.

## Architecture

```
Host (macOS)                              Docker Container
─────────────                             ─────────────────
$ orca add feature-x                      Container: "orca-myproject-feature-x"
$ orca attach feature-x                   stays alive via sleep infinity
                                          ┌─────────────────────────────────┐
tmux window "backend:8000"                │                                 │
  └→ docker exec -it ... bash -c  ──────→ │  python manage.py runserver ... │
tmux window "frontend:5000"               │                                 │
  └→ docker exec -it ... bash -c  ──────→ │  npm run dev ...                │
tmux window "claude"                      │                                 │
  └→ docker exec -it ... bash -c  ──────→ │  claude myproject-feature-x     │
tmux window "shell"                       │                                 │
  └→ docker exec -it ... bash -l  ──────→ │  interactive shell              │
                                          │                                 │
~/Dev/myproject-feature-x/ ─bind mount──→ │  /workspace (rw)                │
~/.ssh/ ────────────────────ro mount────→ │  SSH keys for git               │
~/.gitconfig ───────────────ro mount────→ │  git config                     │
ANTHROPIC_API_KEY ──────────env var─────→ │  Claude Code auth               │
                                          └─────────────────────────────────┘
```

**Key insight**: tmux runs on the host. Each tmux window runs `docker exec -it` into the container. Your `~/.tmux.conf` works perfectly, including clipboard.

## Quick Start

### Prerequisites

- macOS
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [Homebrew](https://brew.sh) (for installing remaining deps)

The installer will automatically install any missing tools via Homebrew: tmux, git, gh, jq, yq.

### Install

**Option 1: One-line installer** (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/rasca/orca/main/install.sh | bash
```

**Option 2: Manual**

```bash
git clone git@github.com:rasca/orca.git ~/Dev/orchestrator
cd ~/Dev/orchestrator && ./install.sh
```

### Usage

```bash
cd ~/Dev/myproject
orca init                    # Generate orchestrator.yml (uses Claude Code)
orca add feature-auth        # Create isolated session
orca attach feature-auth     # Attach to tmux
# ... work in sandboxed environment ...
# Ctrl+B d to detach (or your tmux prefix)
orca list                    # Show all sessions
orca stop feature-auth       # Stop (preserves state)
orca resume feature-auth     # Resume later
orca remove feature-auth     # Clean up everything
```

### PR Review

```bash
orca pr 42                   # Create session from PR #42
orca attach pr-42
# ... review the PR ...
orca remove pr-42
```

## Configuration

Create `orchestrator.yml` in your project root. Run `orca init` to generate one automatically (requires [Claude Code](https://docs.anthropic.com/en/docs/claude-code)), or create it manually:

```yaml
project: myproject
base_branch: main

worktree:
  enabled: true

setup:
  copy:
    - .env
    - .claude/settings.local.json
  env_substitutions:
    ".env":
      API_PORT: "${backend_port}"

docker:
  python_requirements: requirements.txt
  node_install: [frontend]
  volumes:
    node_modules: /workspace/frontend/node_modules

ports:
  backend: { start: 8000 }
  frontend: { start: 5000 }

windows:
  - name: "backend:${backend_port}"
    directory: .
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

env:
  - ANTHROPIC_API_KEY
```

See [examples/orchestrator.yml.example](examples/orchestrator.yml.example) for a full example.

## Commands

| Command | Description |
|---------|-------------|
| `orca build` | Build/rebuild the base Docker image |
| `orca init` | Generate orchestrator.yml for current project |
| `orca add <name>` | Create session (worktree + container + tmux) |
| `orca pr <number>` | Create session from a GitHub PR |
| `orca update-pr <number>` | Pull latest changes into PR session |
| `orca attach <name>` | Attach to session's tmux |
| `orca stop <name>` | Stop container (preserves worktree + volumes) |
| `orca resume [name]` | Restart stopped session(s) |
| `orca remove <name>` | Remove everything (container, volumes, worktree, branch) |
| `orca list` | Show all active sessions |

## State

Session state is stored in `~/.orca/sessions.json`. This keeps state separate from the install directory, so upgrades and reinstalls don't lose your sessions.

Override the location with the `ORCA_STATE_DIR` environment variable:

```bash
export ORCA_STATE_DIR=/custom/path
```

If upgrading from an older version that stored state in `$ORCA_ROOT/state/`, orca will automatically migrate it on first run.

## Claude Code Plugin

orca includes a Claude Code skill. Install it to use `/orca` commands from within Claude Code:

```bash
claude plugin install ~/Dev/orchestrator
```

Then use `/orca init` to have Claude analyze your project and generate an `orchestrator.yml`, or `/orca list` to check session status.

## How It Works

1. **`orca build`** — Builds a base Docker image with Ubuntu 24.04, Node.js 22, Python 3, Git, GitHub CLI, and Claude Code. UID/GID matches your macOS user for correct file permissions.

2. **`orca add <name>`** — Creates a git worktree, starts a Docker container with your project mounted at `/workspace`, installs dependencies, and creates a tmux session on the host where each window runs `docker exec` into the container.

3. **Volume mounts** — Your source code is bind-mounted (rw). Git config, SSH keys, and GitHub CLI auth are mounted read-only. node_modules use Docker named volumes for performance.

4. **Port management** — Ports are auto-allocated globally across all projects and sessions. Servers bind to `0.0.0.0` inside Docker for port forwarding to work.

5. **Safety** — If code inside Docker runs `rm -rf /`, only the container is affected. Your host filesystem is protected. The only host path exposed is the project worktree.

## Development

### Running tests

```bash
brew install bats-core    # one-time setup
make test                 # run all tests
make test-unit            # unit tests only
make test-integration     # integration tests only
```

Tests use temp directories and mock docker/tmux/git — no containers or tmux sessions are created.

## License

MIT
