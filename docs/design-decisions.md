# Design Decisions

This document captures the non-obvious design decisions behind `task-a-llama`
and the reasoning that informed them. It's intended for future-you (and any
collaborator) to understand *why* things are the way they are — especially
when considering changes.

The full exploratory conversation that produced these decisions is archived
separately; this is the curated summary.

---

## Why Vikunja (rather than build from scratch)

Considered: rolling a bespoke Claude Code + SQLite task manager from the ground up.

Rejected because:

- Vikunja already has a mature, battle-tested task data model — hierarchical
  projects, subtasks, labels, reminders, recurrence, dependencies
- It exposes a well-documented REST API and CalDAV interface, giving us
  multiple clean access vectors
- It ships a polished web UI that we'd otherwise have to build or forgo
- The SQLite single-file backend is exactly what we'd have designed anyway
- Writing a task manager is a multi-month project; customising one is a weekend

The "build from scratch" path remains a retreat option if Vikunja stops
meeting needs, but it's a last resort.

---

## Why SQLite (rather than Postgres)

Vikunja supports SQLite, MySQL, and PostgreSQL. We chose SQLite because:

- Single-user workload — Postgres is overkill
- Single file (~10 MB expected for personal use) is trivially backup-able
- Readable by any tool with `sqlite3` installed (macOS ships with it)
- `sqlite3 .dump` produces plain SQL for Git-friendly history
- Online backup API (`.backup` command) gives transaction-safe snapshots
  without stopping the service
- No separate database container to manage

If usage ever outgrows SQLite, Vikunja supports migration to Postgres — but
realistically this won't happen at personal scale.

---

## Why Bind Mounts (rather than named Docker volumes)

Data lives in `~/vikunja-<slug>/db/` and `~/vikunja-<slug>/files/` on the
host filesystem.

Reasons:

- Data is inspectable and backup-able with ordinary filesystem tools
- Migration between Docker runtimes (Docker Desktop to OrbStack to Colima) is
  a 30-second operation with no data movement
- A `tar czf` of `~/vikunja-prod/` is a complete backup of that slug
- Bypasses Docker's opaque storage layer entirely
- Each slug gets its own directory, so multiple environments are trivially
  isolated with no naming conflicts

Named volumes are slightly faster and better-isolated, but the tradeoff
favours transparency and portability for this use case.

---

## VIKUNJA_ variable naming and apparent duplication

Three variables cover similar ground:

- `VIKUNJA_SERVICE_PUBLICURL` (`http://localhost:3456/`) - Docker `.env`
- `VIKUNJA_BASE_URL` (`http://localhost:3456/api/v1`) - TAL env
- `VIKUNJA_PORT` (`3456`) - Docker `.env`

They exist for different reasons and the duplication is largely forced:

**`VIKUNJA_SERVICE_PUBLICURL`** is Vikunja's own config key - the app needs
its externally-visible address for email links and API self-references. The
name ("PUBLIC") is from Vikunja's perspective: the address it's reachable at
from outside the container. We cannot rename or drop it.

**`VIKUNJA_BASE_URL`** is a TAL-side variable (in `~/.config/task-a-llama/<slug>/env`).
The skill and scripts need an API root that works for both local and Cloud
slugs. It must live in the TAL env because Cloud slugs have no Docker env.
The `/api/v1` path suffix is fixed — Vikunja has used it since v1 and v2.x
of the app still does (the path version is the API version, not the app version).

**`VIKUNJA_PORT`** exists because Docker Compose needs a bare integer for port
binding interpolation (`127.0.0.1:${VIKUNJA_PORT}:3456`) and cannot extract a
port number from a URL string.

**One deferred simplification:** `VIKUNJA_SERVICE_PUBLICURL` is fully derivable
from `VIKUNJA_PORT` and could be set inside `docker-compose.yml` directly
(`VIKUNJA_SERVICE_PUBLICURL: "http://localhost:${VIKUNJA_PORT}/"`) rather than
carried as a user-configurable key in `.env`. This would reduce the configurable
surface by one variable. Left for later as the current setup works and the
redundancy is low-risk.

---

## Why Four Repos (rather than one)

The project splits across `task-a-llama` (framework), `task-a-llama-skills`
(public skills), `task-a-llama-overlay` (private skills), and
`task-a-llama-pasture` (data).

Each has a distinct:

- **Visibility** — framework and public skills are potentially public;
  overlay and data are strictly private
- **Churn rate** — framework changes occasionally, data commits nightly,
  skills evolve in between
- **Audience** — framework and public skills could benefit others; overlay
  and data are personal
- **Lifecycle** — if Vikunja gets replaced, framework deprecates but skills
  knowledge lives on; data is forever

Mixing them would pollute Git history, block public sharing, and create
backup-strategy conflicts.

The four repos are connected at runtime via the framework's `config.yml`,
which is the only place cross-repo paths live. This keeps dependencies
unidirectional (framework → others) and makes renames/relocations cheap.

---

## Why Stow-Managed (rather than install scripts)

This project assumes GNU Stow is available and will be used for symlinking
framework files into runtime locations.

Stow gives us:

- Idempotent installation (re-stow is safe)
- Clean uninstall (unstow removes symlinks without data loss)
- Consistency with existing dotfiles workflow (the user already uses stow)
- No custom install logic to maintain

The alternative — bespoke install/uninstall scripts — is more flexible but
also more error-prone and less predictable.

---

## Why Separate Knowledge from AI Runtime Packaging

The public skills repo deliberately splits:

```
knowledge/              # AI-agnostic markdown describing Vikunja
adapters/claude-code/   # Thin SKILL.md wrappers that reference knowledge/
adapters/cursor/        # Future: Cursor-format wrappers
```

Reasons:

- Knowledge is the hard part; packaging is boilerplate
- AI runtimes churn faster than the underlying tool; decoupling protects
  the expensive artifact from format shifts
- Same knowledge can serve multiple AI tools with only adapter additions
- Forces the knowledge to stand on its own, improving its quality for
  human readers too

Only `adapters/claude-code/` exists today; others get added if/when needed.

---

## Why Pin Docker Images to Minor Version

Compose file uses `vikunja/vikunja:2.3` rather than `:latest` or `:2.3.0`.

- `:latest` risks surprise major-version upgrades with schema migrations
- `:2.3.0` is fully pinned -- never gets patch updates, including security fixes
- `:2.3` gets patch updates (2.3.0 -> 2.3.1 -> ...) but never jumps to 2.4

Vikunja's Docker Hub tags use no `v` prefix (e.g. `2.3`, `2.3.0`), unlike
some other projects. Watchtower uses the same un-prefixed convention.

Watchtower runs in monitor-only mode — it notifies of available updates
without applying them, letting us read release notes before upgrading minors
or majors deliberately.

---

## Why `task-a-llama` as a Name

Considered and rejected:

- `vikunja-framework` — accurate but buries the AI-augmentation angle
- `vikunja-ai-framework` / `vikunja-ai-kit` — clear but bland
- `herd` — too many existing "Herd" projects (Laravel Herd, FINRA Herd,
  parallel SSH tool); FINRA's data-catalog namesake is awkward given
  DataHub day-job context
- `weave`, `poncho`, `troop` — distinctive but no strong reason to pick
  over `task-a-llama`

`task-a-llama` won because:

- Distinctive and memorable
- Phonetically on-theme (camelid family, honouring Vikunja's naming tradition)
- Verb framing reads naturally as AI delegation ("task a llama with syncing")
- Extends cleanly to sibling repos (`-skills`, `-overlay`, `-pasture`)
- Short alias `tal` is unclaimed

The `-llama` rather than `-vicuña` reflects that most people know llamas,
and LLMs (meta-Llama especially) have made "llama" shorthand for the AI
augmentation angle.

---

## Decisions Explicitly Deferred

The following decisions were considered but deferred:

- **OrbStack vs Docker Desktop** — Docker Desktop is fine for current scale;
  OrbStack migration is a 5-minute job when/if performance becomes an issue
- **Dockge or similar stack-manager UI** — single stack doesn't warrant it
  yet; revisit when 3+ stacks exist
- **Claude.ai / mobile access** — would require Tailscale/tunnel to expose
  Vikunja beyond localhost; deferred until there's genuine demand
- **Postgres migration** — won't happen unless SQLite demonstrably strains,
  which it won't at personal scale
- **CalDAV client setup** — documented as possible, not pre-configured

Each of these has a clear upgrade path if needed.
