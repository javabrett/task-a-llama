# Setup

Full walkthrough from fresh clone to a running Vikunja. This complements the
abbreviated Quick Start in [README.md](../README.md) with the detail you'll
want on a first install.

## Prerequisites

All installed and on `PATH`:

| Tool | Why | How |
| --- | --- | --- |
| Docker (with `docker compose` subcommand) | Runs the Vikunja container | Docker Desktop, [OrbStack](https://orbstack.dev/), or [Colima](https://github.com/abiosoft/colima) |
| `yq` | Parses `config.yml` | `brew install yq` |
| `sqlite3` | Used by backup / restore scripts | Ships with macOS; otherwise `brew install sqlite` |
| `git` | Clones the public skills repo (Phase 2 onward) | `xcode-select --install` or `brew install git` |
| `openssl` | Generates the JWT secret | Ships with macOS |

`bin/bootstrap.sh` checks all of these and fails fast with a clear hint if
anything is missing.

## 1. Clone the framework

```bash
git clone https://github.com/javabrett/task-a-llama ~/src/task-a-llama
cd ~/src/task-a-llama
```

The framework repo lives at `~/src/task-a-llama` in these examples. You can
put it anywhere; `config.yml` records the separate runtime directory.

## Companion repos (optional for Phase 1)

`task-a-llama` orchestrates three companion repos via `config.yml`. None of
them need to exist for Vikunja to run; bootstrap warns and continues if they
are absent.

| Repo | Purpose | Required for |
| --- | --- | --- |
| `task-a-llama-skills` | Public skills repo -- the `/tal` Claude Code skill | Phase 2 (not built yet) |
| `task-a-llama-overlay` | Private skills overlay, managed by your mac-setup dotfiles | Phase 2 |
| `task-a-llama-pasture` | SQL dump history -- committed by `backup.sh --commit` | Backup `--commit`/`--push` flags |

Bootstrap will clone `task-a-llama-skills` automatically once it exists. The
other two are never cloned by bootstrap; you manage them yourself.

For a Phase 1 install you can leave all three paths as placeholders in
`config.yml` and address them when Phase 2 lands.

## 2. Configure

```bash
cp config.example.yml config.yml
$EDITOR config.yml
```

At minimum, confirm:

- `runtime_dir` - where Vikunja's live data will live. Default `~/vikunja`.
- `sources.public_skills.local` - where to clone the public skills repo.
- `sources.private_skills.path` - expected path; bootstrap only verifies.
- `sources.data.local` - where the `task-a-llama-pasture` data repo lives.
- `backup.binary_dir`, `backup.sql_dump_target`, `backup.retention_days`.

Paths may use a leading `~` - the scripts expand it safely.

`.env` is seeded automatically on the first bootstrap run (see next step).

## 3. Run bootstrap

```bash
./bin/bootstrap.sh
```

This:

1. Validates prerequisites
2. Creates `runtime_dir/{db,files}`
3. Symlinks `docker-compose.yml` into `runtime_dir`
4. Creates `runtime_dir/.env` from `.env.example` and generates a JWT secret
5. Clones the public skills repo if configured (warning, not fatal, if the
   remote doesn't exist yet)
6. Verifies the private skills and data repo paths exist (warning only -
   bootstrap never clones private repos for you)
7. Offers to bring the stack up with `docker compose up -d`

Bootstrap is idempotent. Re-running it is safe; each step is a no-op when
already complete. Steps that could clobber local edits (e.g. `.env`) are
left alone if they exist.

After the first run, review `runtime_dir/.env` and confirm `TZ` matches your
actual timezone.

## 4. First login

```bash
open http://localhost:3456
```

Register an account. The first user registered becomes the admin.

Once registered, close the registration loophole:

```bash
$EDITOR ~/vikunja/.env        # set VIKUNJA_SERVICE_ENABLEREGISTRATION=false
./bin/restart.sh
```

## 5. Create an API token (for Phase 2)

Phase 1 does not require an API token - the infrastructure runs without
Claude Code integration. When you're ready for Phase 2 (the `/tal` skill):

1. In Vikunja: Settings -> API Tokens -> Create token
2. Copy the `tk_...` value
3. Paste it into `~/vikunja/.env` as `VIKUNJA_API_TOKEN`
4. `./bin/restart.sh`

Scope the token narrowly to the operations your skill will need (Vikunja's
token UI lets you pick specific routes).

## 6. Verify

Manual checks:

```bash
./bin/up.sh                          # stack is up
open http://localhost:3456           # UI responds, you can log in
./bin/backup.sh                      # produces both a .tgz and a SQL dump
./bin/down.sh                        # stack stops cleanly
```

At this point you have a running, backup-able Vikunja. AI integration lands
in a follow-up session - see [README.md](../README.md) and the Phase 2 plan.

## Troubleshooting

**`docker: command not found`** - install Docker Desktop or OrbStack.

**`yq: command not found`** - `brew install yq`. Note: the scripts assume
[mikefarah/yq](https://github.com/mikefarah/yq) (the Go binary shipped by
Homebrew), not the Python wrapper.

**`config.yml not found`** - bootstrap will copy `config.example.yml` for
you on its first run and then exit so you can edit it. Re-run bootstrap
once you're happy with the config.

**`runtime_dir does not exist`** (from `up.sh` etc.) - you haven't run
`bootstrap.sh` yet. Run it first.

**Port 3456 already in use** - change the host-side port in
`docker-compose.yml` (the `"127.0.0.1:3456:3456"` line) and re-run bootstrap.

**`VIKUNJA_SERVICE_ENABLEREGISTRATION` not taking effect** - docker compose
re-reads `.env` only on `up` / `restart`. Use `./bin/restart.sh` after
editing `.env`.

See [docs/backup-restore.md](backup-restore.md) for backup / restore workflows
and [docs/design-decisions.md](design-decisions.md) for the rationale behind
these choices.
