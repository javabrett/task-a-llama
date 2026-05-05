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
| `git` | Clones the public skills repo | `xcode-select --install` or `brew install git` |
| `openssl` | Generates the JWT secret | Ships with macOS |

`bin/bootstrap.sh` checks all of these and fails fast with a clear hint if
anything is missing.

## 1. Clone the framework

```bash
git clone https://github.com/javabrett/task-a-llama ~/src/task-a-llama
cd ~/src/task-a-llama
```

The framework repo lives at `~/src/task-a-llama` in these examples. You can
put it anywhere; `config.yml` records the companion repo paths.

## Companion repos (optional initially)

`task-a-llama` orchestrates three companion repos via `config.yml`. None of
them need to exist for Vikunja to run; bootstrap warns and continues if they
are absent.

| Repo | Purpose | Required for |
| --- | --- | --- |
| `task-a-llama-skills` | Public skills repo -- the `/tal` Claude Code skill | Skill usage |
| `mac-setup/dotfiles/task-a-llama` | Private overlay package (overlay.yml and future private skills), stowed from your dotfiles repo | Custom conventions |
| `task-a-llama-pasture` | SQL dump history -- committed by `backup.sh --commit` | Backup `--commit`/`--push` flags |

Bootstrap will clone `task-a-llama-skills` automatically once it exists. The
other two are never cloned by bootstrap; you manage them yourself.

## 2. Configure

```bash
cp config.example.yml config.yml
$EDITOR config.yml
```

At minimum, confirm:

- `sources.public_skills.local` - where to clone the public skills repo.
- `sources.private_skills.path` - expected path; bootstrap only verifies.
- `sources.data.local` - where the `task-a-llama-pasture` data repo lives.
- `backup.binary_dir`, `backup.sql_dump_target`, `backup.retention_days`.

Paths may use a leading `~` - the scripts expand it safely.

The Docker runtime directory (`~/vikunja-<slug>/`) is derived automatically
from the slug name; it is not configured in `config.yml`.

## 3. Bootstrap the prod slug

```bash
./bin/bootstrap.sh prod
```

This:

1. Validates prerequisites
2. Creates `~/vikunja-prod/{db,files}`
3. Symlinks `docker-compose.yml` into `~/vikunja-prod/`
4. Creates `~/vikunja-prod/.env` from `.env.example` and generates a JWT secret
5. Creates `~/.config/task-a-llama/prod/env` with a placeholder API token
6. Clones the public skills repo if configured (warning, not fatal, if the
   remote does not exist yet)
7. Verifies the private skills and data repo paths exist (warning only -
   bootstrap never clones private repos for you)
8. Offers to bring the stack up with `docker compose up -d`

Bootstrap is idempotent. Re-running it is safe; each step is a no-op when
already complete. Steps that could clobber local edits (e.g. `.env`) are
left alone if they exist.

`TZ` and `VIKUNJA_SERVICE_TIMEZONE` are auto-populated from `/etc/localtime`
so the container timezone matches your system.

## 4. Set the active slug

```bash
./bin/mode.sh prod
```

This verifies the stack is reachable and writes `prod` to
`~/.config/task-a-llama/active`. All subsequent `bin/` and `/tal` operations
default to this slug when no slug argument is given.

## 5. First login

When bootstrap brings the stack up for the first time, it creates your initial
account automatically via the Vikunja CLI running inside the container. No
browser registration step is needed; `VIKUNJA_SERVICE_ENABLEREGISTRATION` stays
`false` throughout.

Bootstrap prints the credentials when it's done:

```
================================================================
  Initial account created - save these in your password manager
  URL:      http://localhost:3456
  Username: admin
  Password: <generated>
================================================================
```

Save the password in your password manager, then open the URL and log in.

If you brought the stack up separately (e.g. `./bin/up.sh`), create the account
manually the same way bootstrap does:

```bash
docker exec vikunja-prod /app/vikunja/vikunja user create \
  --username admin \
  --email    admin@localhost \
  --password "$(openssl rand -base64 18)"
```

## 6. Create an API token and install the `/tal` skill

The Claude Code integration uses a Vikunja API token plus a stowed skill.
Both are one-time setup per slug.

### Create the token

```bash
./bin/first-run.sh prod
```

This opens the Vikunja API Tokens UI in your browser, prompts you to paste
the `tk_...` value, verifies it against the API, and writes it to
`~/.config/task-a-llama/prod/env`. Re-running it is a no-op when a real
token is already present.

If you prefer to do it manually:

1. In Vikunja: Settings -> API Tokens -> Create. Name it `claude-code-prod`.
   Scope to the minimum: projects, tasks, labels (read + write).
2. Copy the `tk_...` value.
3. Edit `~/.config/task-a-llama/prod/env` and set `VIKUNJA_API_TOKEN=tk_...`.
   No restart needed - the skill reads the file on demand.

### Install the skill

The `/tal` skill ships from the [task-a-llama-skills](https://github.com/javabrett/task-a-llama-skills)
repo. Clone and link it:

```bash
git clone https://github.com/javabrett/task-a-llama-skills ~/src/task-a-llama-skills
mkdir -p ~/.claude/skills
ln -s ~/src/task-a-llama-skills/adapters/claude-code/.claude/skills/tal \
      ~/.claude/skills/tal
```

Confirm:

```bash
ls -la ~/.claude/skills/tal/SKILL.md   # should resolve through the symlink
```

In any Claude Code session, try:

```
add a todo to vikunja: write the phase 2 retro
```

The skill matches on natural-language phrases and asks for confirmation
before creating anything. See `~/.claude/skills/tal/SKILL.md` for the
full safety contract and the working-directory -> project mapping rules.

### Optional: install the backup LaunchAgent

```bash
./bin/install-launchd.sh prod
```

Loads `bin/launchd/com.task-a-llama.backup.plist` into launchd to run
`backup.sh prod --commit` daily at 04:00. Idempotent. Uninstall with
`./bin/install-launchd.sh --uninstall`. See
[backup-restore.md](backup-restore.md) for details.

### Optional: global Claude Code awareness

[`global-claude-md-proposal.md`](global-claude-md-proposal.md) drafts a
small section to add to your `~/.claude/CLAUDE.md` so Claude Code
understands the framework's conventions across all sessions. Read and
paste by hand; the framework deliberately doesn't auto-edit your global
config.

## 7. Verify

Manual checks:

```bash
./bin/up.sh prod                     # stack is up
open http://localhost:3456           # UI responds, you can log in
./bin/backup.sh prod                 # produces both a .tgz and a SQL dump
./bin/down.sh prod                   # stack stops cleanly
```

In Claude Code (after installing the skill): ask "what's open in vikunja?"
or "add a todo to vikunja: ..." and confirm the skill responds with a
paraphrase before creating anything. The response will be prefixed `[prod]`.

## Troubleshooting

**`docker: command not found`** - install Docker Desktop or OrbStack.

**`yq: command not found`** - `brew install yq`. Note: the scripts assume
[mikefarah/yq](https://github.com/mikefarah/yq) (the Go binary shipped by
Homebrew), not the Python wrapper.

**`config.yml not found`** - bootstrap will copy `config.example.yml` for
you on its first run and then exit so you can edit it. Re-run bootstrap
once you're happy with the config.

**No active environment selected** - run `bin/mode.sh <slug>` to set the
active slug before running commands without an explicit slug argument.

**Port 3456 already in use** - choose a different port when bootstrap prompts
for it (or pass a different slug, e.g. `bin/bootstrap.sh myprod`).

**Can't log in after a fresh install** - check that bootstrap completed
successfully. If you brought the stack up manually, create the initial account
via `docker exec` (see step 5 above).

See [docs/backup-restore.md](backup-restore.md) for backup / restore workflows
and [docs/design-decisions.md](design-decisions.md) for the rationale behind
these choices.

## Running multiple environments

Once you are using `/tal` for real task management, you may want a disposable
test slug. See [docs/multi-environment.md](multi-environment.md) for setup
and switching.

## Migrating from an older prod/test layout

If you installed the framework before the slug restructuring:

```bash
./bin/migrate-to-slugs.sh
```

This is a one-shot, idempotent migration that moves `~/vikunja/` to
`~/vikunja-prod/`, splits the API token and URL out of `.env` into
`~/.config/task-a-llama/prod/env`, and renames `active-mode` to `active`.
