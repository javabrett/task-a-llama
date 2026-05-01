# task-a-llama

**AI-augmented personal task management, built on Vikunja and Claude Code.**

`task-a-llama` is a framework for running a self-hosted [Vikunja](https://vikunja.io/) task manager on your local Mac, wrapped in the tooling, skills, and conventions needed to make it a first-class citizen in a Claude Code workflow. Tasks captured mid-session in Claude Code land in Vikunja automatically; bulk operations, reporting, and cross-project reviews happen through natural language; and the whole setup is reproducible, version-controlled, and portable.

It's designed for people who want Asana-style lightweight task management with two different interaction vectors — an AI-driven one for capture and bulk work, and a traditional web UI for the loop-update moments — without paying for either the SaaS or the complexity of a team-oriented tool.

---

## What This Is (and Isn't)

**This is:** a reproducible infrastructure setup plus an AI-augmentation layer. The framework handles Vikunja deployment; the skills layer teaches Claude Code how to operate Vikunja well on your behalf.

**This isn't:** a Vikunja replacement, a new task manager, or a general-purpose agent platform. Vikunja does the actual work. `task-a-llama` just makes Vikunja pleasant to live with.

---

## Highlights

- **Single-container Vikunja** with SQLite backend, running on localhost via Docker (or OrbStack, or Colima — the runtime doesn't matter)
- **Claude Code skills** for common operations: capture TODOs from a session into Vikunja, sync Linear issues, daily reviews, backup/restore
- **Minimal bind-mount footprint** — one SQLite file plus an attachments directory, nothing else persistent
- **GitOps-style backup** — binary snapshots for point-in-time restore, SQL dumps committed to a private data repo for diffable history
- **Stow-managed deployment** — framework files live in source control, symlinked into runtime location via [GNU Stow](https://www.gnu.org/software/stow/)
- **AI-runtime-agnostic knowledge** — the public skills repo separates reusable Vikunja knowledge (plain markdown) from Claude-specific packaging (SKILL.md format), making it straightforward to add adapters for other AI runtimes later
- **Separated concerns across four repos** — framework, public skills, private overlay, data

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ macOS                                                       │
│                                                             │
│  ┌──────────────────────────────────────────────────┐       │
│  │ Docker Runtime (Docker Desktop / OrbStack)       │       │
│  │                                                  │       │
│  │  ┌─────────────────┐      ┌──────────────────┐   │       │
│  │  │ Vikunja         │      │ Watchtower       │   │       │
│  │  │ :3456           │      │ (monitor-only)   │   │       │
│  │  └────────┬────────┘      └──────────────────┘   │       │
│  └───────────┼──────────────────────────────────────┘       │
│              │                                              │
│              │ bind mounts                                  │
│              ▼                                              │
│    ~/vikunja-prod/db/vikunja.db   (SQLite -- the data)      │
│    ~/vikunja-prod/files/          (attachments)             │
│    ~/vikunja-prod/.env            (Docker secrets)          │
│    ~/.config/task-a-llama/prod/env  (URL + API token)       │
│                                                             │
│     ▲                 ▲                    ▲                │
│     │                 │                    │                │
│  Claude Code      Web browser        (optional later)       │
│  (bash / REST     (localhost UI)     Apple Reminders        │
│   API only)                          via CalDAV             │
└─────────────────────────────────────────────────────────────┘
```

Three access vectors, one source of truth. The web UI handles quick-check and touch-up; Claude Code handles capture, bulk work, and reporting; CalDAV (optional) would handle mobile sync if you later decide to expose Vikunja beyond localhost.

Multiple named environments (slugs) can coexist — a local `prod` stack and a `test` stack, or local stacks alongside Vikunja Cloud. Each slug carries its own URL and token; `bin/mode.sh <slug>` switches between them.

---

## The Four-Repo Structure

`task-a-llama` is intentionally split across four repositories, each with its own lifecycle and privacy posture:

| Repo                         | Visibility       | Contents                                                        | Churn          |
| ---------------------------- | ---------------- | --------------------------------------------------------------- | -------------- |
| `task-a-llama`               | Potentially public | Docker Compose, scripts, bootstrap, config schema, README       | Low            |
| `task-a-llama-skills`        | Public           | AI-agnostic Vikunja knowledge + Claude Code adapter             | Low-to-medium  |
| `task-a-llama-overlay`       | Private          | Personal skills, customer context, personal conventions          | Medium         |
| `task-a-llama-pasture`       | Private          | SQL dumps of task database, committed on every backup cycle     | Daily          |

**Framework** (`task-a-llama`) is AI-agnostic infrastructure. It knows nothing about Claude; it just runs Vikunja and orchestrates the other repos via a config file.

**Public skills** (`task-a-llama-skills`) carry reusable Vikunja knowledge — API reference, schema, common queries, safe operating patterns. The knowledge lives as plain markdown; an `adapters/claude-code/` subtree repackages it as Claude Code `SKILL.md` files. Future adapters for Cursor, Aider, or Codex drop into sibling subtrees without touching the knowledge itself.

**Private overlay** (`task-a-llama-overlay`) holds the personal bits: customer lists, project conventions, Linear sync field mappings, writing-style preferences. Lives inside the user's dotfiles repo (stow-managed) rather than as a standalone repo.

**Data** (`task-a-llama-pasture`) is the SQL dump history — regenerated nightly, committed to Git, pushed to a private remote. Every commit is a snapshot; every diff is a change report.

Each repo could be used independently, but the framework config binds them together at runtime.

---

## What Claude Code Can Do With This

Once set up, the following work through natural language in any Claude Code session:

- **Capture**: *"Add these TODOs to Vikunja under the MoneyLion project: follow up on ingestion config, draft security questionnaire response, book a follow-up call"*
- **Review**: *"What are my open tasks for Rakuten, sorted by priority?"*
- **Bulk operations**: *"Mark all the 'waiting' tasks on the LG Ad Solutions project as 'next' — we're unblocked now"*
- **Reporting**: *"Give me a daily summary of what I closed out this week, grouped by customer"*
- **Cross-tool sync**: *"Pull my assigned Linear issues and reconcile with Vikunja"* (via the `linear-vikunja-sync` skill)
- **Backup / maintenance**: *"Run the task database backup and push the dump to the pasture repo"*

The skills encapsulate how to do these reliably — with dry-run defaults on destructive operations, with paraphrased summaries of what will happen before anything mutates, and with consistent field mappings across sessions.

---

## Runtime Footprint

- **Vikunja**: ~30-50 MB RAM idle, negligible CPU
- **Watchtower**: ~10 MB RAM
- **Total disk**: SQLite file stays under 10 MB for personal use indefinitely; attachments directory depends on usage (typically empty for TODO-style workflows)
- **Network**: localhost only by default; no public exposure unless intentionally configured
- **Boot time**: seconds, via `docker compose up -d`

No daemon processes beyond the Docker containers. No cloud dependencies. No accounts except the local Vikunja account.

---

## Quick Start

```bash
# 1. Clone the framework
git clone https://github.com/javabrett/task-a-llama ~/src/task-a-llama
cd ~/src/task-a-llama

# 2. Copy config template and fill in your paths
cp config.example.yml config.yml
$EDITOR config.yml

# 3. Bootstrap the prod slug -- validates prereqs, seeds the Docker .env with
#    a generated JWT secret, and creates the TAL-side env file
./bin/bootstrap.sh prod

# 4. Bring the stack up and set the active slug
./bin/up.sh prod
./bin/mode.sh prod

# 5. First login - bootstrap prints credentials when the stack comes up
open http://localhost:3456
# Log in with the username/password printed by bootstrap.
# Save them in your password manager.

# 6. Create a Vikunja API token for Claude Code
# In Vikunja: Settings -> API Tokens -> Create.
# Then run the token setup script:
./bin/first-run.sh prod
```

Full setup details in [docs/setup.md](docs/setup.md).

---

## Key Design Decisions

A few choices that shape how this project feels in use:

### SQLite over Postgres
Postgres is overkill for single-user task management. SQLite gives us a single-file database that's trivially backup-able, grep-able with `sqlite3 .dump`, readable by any tool in the ecosystem, and fast enough for personal scale. If you ever outgrow it, Vikunja supports migrating to Postgres — but you almost certainly won't.

### Bind mounts over named Docker volumes
The data lives in `~/vikunja-<slug>/db/` on the host filesystem, not inside Docker's opaque storage. This means migrating Docker runtimes (Docker Desktop to OrbStack, say) is a 30-second operation with no data movement. It also means `tar czf vikunja.tgz ~/vikunja-prod` is a complete backup of that slug.

### SQL dumps in Git over binary snapshots
Binary SQLite files in Git work technically but waste space and lose diff-ability. Committing `sqlite3 .dump` output as plain SQL means Git's delta compression actually works, and `git diff` shows you exactly which tasks changed between backups. The data repo becomes a readable history of your task life.

### Separated knowledge from adapters
The public skills repo keeps Vikunja knowledge in plain markdown (`knowledge/api-reference.md`) separate from AI-runtime packaging (`adapters/claude-code/.claude/skills/...`). This means adding support for a new AI runtime is a wrapper exercise, not a rewrite.

### Framework as orchestrator
Only the framework repo knows about the other three. The skills repo doesn't know where data lives; the data repo doesn't know about skills. Cross-repo paths flow through the framework's `config.yml`. This keeps each repo focused and makes renames / relocations cheap.

### Pin Docker images to minor versions
`vikunja/vikunja:2.3` rather than `latest` or `2.3.0`. Gets patch updates through Watchtower without being surprised by major version changes that might include schema migrations. Note: Vikunja's Docker Hub tags have no `v` prefix.

---

## Backup & Recovery

Three layers, automated via LaunchAgent:

1. **Point-in-time binary snapshots** — `sqlite3 .backup` creates transaction-safe copies of the DB. Rolling 7-day retention in `~/backups/task-a-llama/`.
2. **SQL dump to Git** — `sqlite3 .dump` writes a text representation of the entire database. Committed to the `task-a-llama-pasture` repo on every backup cycle. Diffable, compressible, portable across SQLite versions.
3. **Attachments folder** — only matters if tasks have attachments. Included in the tarball backup but usually empty for TODO-style workflows.

Restore is equally straightforward: stop Vikunja, replace `~/vikunja-<slug>/db/vikunja.db` with a snapshot, restart. See [docs/backup-restore.md](docs/backup-restore.md).

---

## Security Posture

Designed for single-user localhost deployment:

- No public network exposure by default; Vikunja listens on `localhost:3456` only
- Secrets (JWT secret, API tokens) live in `.env`, gitignored, never committed
- Registration disabled after initial user creation
- API tokens are scoped per-use — one for Claude Code, one for any other integration
- CORS disabled because frontend and API share an origin

If you later choose to expose Vikunja beyond localhost (Tailscale, reverse proxy), additional hardening applies — see [docs/exposing-remotely.md](docs/exposing-remotely.md).

---

## What's Deliberately Not Included

- **Multi-user support** — Vikunja supports it; this framework assumes you're the only user
- **Cloud deployment recipes** — the framework targets localhost; VPS deployment is out of scope
- **CalDAV client setup** — Vikunja exposes CalDAV endpoints, but configuring Apple Reminders / Thunderbird / etc. is left to the user
- **Alternative backend migrations** — MySQL/Postgres support exists in Vikunja but isn't addressed here
- **Non-Vikunja backends** — the framework is Vikunja-specific; if Vikunja stops meeting your needs, this framework stops being relevant

---

## Roadmap

v1.0 (current):
- Vikunja + Watchtower compose stack
- Bootstrap / backup / restore scripts
- Claude Code adapter with core skills (capture, review, backup)
- Public knowledge base for Vikunja API

Considered for later:
- Linear ↔ Vikunja bidirectional sync skill (currently pull-only)
- Additional AI runtime adapters (Cursor, Aider)
- CalDAV quick-setup helper for Apple Reminders sync
- Optional Postgres migration path for users who outgrow SQLite

Not considered:
- Multi-user / team features
- Mobile apps (use Vikunja's PWA or a CalDAV client)
- Replacing any component of Vikunja itself

---

## Credits & Prior Art

- [Vikunja](https://vikunja.io/) — does all the actual work; this is just scaffolding around it
- [democratize-technology/vikunja-mcp](https://github.com/democratize-technology/vikunja-mcp) — community MCP server; optional but useful for richer Claude Code tool semantics
- [GNU Stow](https://www.gnu.org/software/stow/) — the unsung hero of dotfile-style deployment
- [Taskwarrior](https://taskwarrior.org/) — influenced the data model thinking, even though we ended up deferring to Vikunja's schema
- [Todo.txt](http://todotxt.org/) — proof that plain-text task management can be powerful

---

## License

Framework and public skills: MIT (proposed — finalise before first public push).

Private overlay and data repos remain private.

---

*Named in the Vikunja tradition of honouring South American camelids, with appreciation for the fact that "task a llama" is exactly what this project lets you do.*
