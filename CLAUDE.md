# CLAUDE.md — task-a-llama framework repo

This is the `task-a-llama` framework repository: the infrastructure-as-code for running
a self-hosted Vikunja instance with Claude Code integration.

Read `README.md` first for project overview, structure, and design decisions.

## What this repo is

- Infrastructure layer only: Docker Compose, bootstrap scripts, backup scripts, config schema
- AI-agnostic — knows nothing about Claude Code or MCP directly
- One of four related repos (framework, skills, overlay, data); this is the framework

## What this repo is not

- Not the place for AI skills or prompts — those live in `task-a-llama-skills` (public)
  or `task-a-llama-overlay` (private, inside user dotfiles)
- Not the place for task data — that lives in `task-a-llama-pasture` (private data repo)
- Not a multi-user or team tool — single user, localhost deployment

## Conventions

- Docker images pinned to minor version (e.g. `2.3`), not `latest`; Vikunja tags have no `v` prefix
- Bind mounts, not named volumes, for all persistent data
- Secrets in `.env` (gitignored); shape documented in `.env.example` (committed)
- Cross-repo paths configured in `config.yml` (gitignored); shape in `config.example.yml`
- Scripts live in `bin/`, docs in `docs/`, both under source control
- Follow existing shell style in `bin/` when adding new scripts (bash, `set -euo pipefail`)

## When making changes

- Update `README.md` if design decisions change
- Update `.env.example` and `config.example.yml` when adding new config knobs
- Keep scripts idempotent — they should be safe to re-run
- Preserve the four-repo separation — don't pull skills or data concerns into this repo

## Useful files to read for context

- `README.md` — project overview and design decisions
- `docs/design-decisions.md` — deeper rationale for non-obvious choices
- `docker-compose.yml` — the runtime stack definition
- `config.example.yml` — orchestration config schema

## Vikunja REST conventions

When making Vikunja API calls (via curl or skill operations), always return
a direct URL to the affected resource after any successful mutation:

- Project: `http://localhost:3456/projects/{id}`
- Task: `http://localhost:3456/tasks/{id}`
- Comment: `http://localhost:3456/tasks/{task_id}#comment-{comment_id}`

This applies whether the call is a one-off debug curl or part of a skill
operation. Don't make the user hunt in the UI.

## Task ID system

Vikunja has two distinct task identifiers:

- **Global ID** (`task.id`) -- the database primary key, used in all API calls and URLs (e.g. `/tasks/17`). This is the only identifier the skill uses.
- **Project index** (`task.index`) -- a per-project sequential counter shown in the UI as `#10`, or `TAL-10` if the project has an identifier prefix set. This is display-only; it cannot be used in API calls in released Vikunja versions.

In practice: when referring to a task in a `/tal` prompt, use the global ID from the browser URL bar. The skill will always echo back global IDs and full URLs. The project-scoped `#N` shown in the task heading can be ignored.

A `GET /tasks/by-ref/{ref}` endpoint that would allow the full string identifier (e.g. `TAL-10`) to be used directly in API calls has been proposed in go-vikunja/vikunja#2694. If that lands and is adopted here, this constraint can be revisited.

See also: `docs/vikunja-ui-tweaks.md` for a CSS rule to hide the confusing project index from the task heading.

## Source references

Vikunja's own source code is checked out at `repos/vikunja/` (gitignored).
Consult it directly when you need authoritative answers about Vikunja's API,
schema, or internal behaviour — rather than guessing or searching the web.
This is a standing convention for this repo.
