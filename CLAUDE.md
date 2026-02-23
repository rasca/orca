# orca — Development Guide

## Project Overview

orca is a Docker-isolated development session orchestrator. It creates sandboxed dev environments where tmux runs on the host and each window executes commands inside a Docker container via `docker exec`.

## Architecture

- `bin/orca` — Main CLI entry point (bash)
- `lib/*.sh` — Library modules sourced by the CLI
- `docker/Dockerfile` — Base container image (Ubuntu + Node + Python + Git + Claude Code)
- `skills/orca/SKILL.md` — Claude Code plugin skill
- `state/sessions.json` — Runtime state (gitignored)

## Key Design Decisions

1. **tmux on host, not in container**: Each tmux window runs `docker exec -it` into the container. This preserves the user's tmux config and clipboard integration.

2. **Single shared base image**: All sessions use `orca-base:latest`. Project-specific deps are installed at session creation time via `docker exec`.

3. **UID/GID matching**: The Dockerfile accepts `DEV_UID` and `DEV_GID` build args to match the host user, avoiding permission issues with bind mounts.

4. **Named volumes for performance**: node_modules and venvs use Docker named volumes to bypass macOS bind mount slowness.

5. **Global port allocation**: Ports are allocated across all projects from `state/sessions.json` to prevent conflicts.

## Working on This Project

- Config parsing uses `yq` (YAML) and `jq` (JSON)
- All library functions are in `lib/` and sourced by `bin/orca`
- The `orchestrator.yml` spec is documented in `skills/orca/references/orchestrator-yml-spec.md`
- Test changes by running `orca` commands directly from `./bin/orca`
