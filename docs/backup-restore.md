# Backup & Restore

Vikunja stores everything you care about in two places: the SQLite database
file and the attachments directory. `task-a-llama` wraps them in a
three-layer backup strategy.

## What gets backed up

| Layer | Format | Location | Purpose |
| --- | --- | --- | --- |
| Binary snapshot | `.tgz` (SQLite file + `files/`) | `backup.binary_dir` | Point-in-time, fast restore |
| SQL dump | Plain SQL from `sqlite3 .dump` | `backup.sql_dump_target` (inside the data repo) | Diffable Git history, portable across SQLite versions |
| Attachments | Included in the binary snapshot | n/a | Usually empty for TODO-style workflows |

The binary snapshot is created via SQLite's online `.backup` API, which is
transaction-safe while the database is being written. You do not need to
stop Vikunja to take a backup.

Rationale for the two-layer approach is in [design-decisions.md](design-decisions.md)
(search for "SQL dumps in Git").

## Running a backup

Manual:

```bash
./bin/backup.sh
```

Produces:

- `backup.binary_dir/task-a-llama-YYYY-MM-DD-HHMMSS.tgz` (new file per run)
- `backup.sql_dump_target` (overwritten each run)

Prunes any `task-a-llama-*.tgz` files older than `backup.retention_days`
(default 7) from `backup.binary_dir`. Files not matching the naming pattern
are never deleted.

### Committing the SQL dump

```bash
./bin/backup.sh --commit
```

Git-adds and commits `backup.sql_dump_target` inside the data repo at
`sources.data.local`. Does not push.

```bash
./bin/backup.sh --push
```

As `--commit`, then `git push`. Useful when you're running interactively
and have SSH credentials loaded; not recommended for unattended LaunchAgent
invocation (see below).

## Scheduled backups (LaunchAgent)

A LaunchAgent plist template lives at `bin/launchd/com.task-a-llama.backup.plist`.
It runs `backup.sh --commit` daily at 04:00 local time.

### Install

```bash
./bin/install-launchd.sh
```

The helper substitutes the framework `bin/` and log paths into the
template, writes the result to `~/Library/LaunchAgents/`, then
`launchctl bootstrap`s it. Idempotent: re-running cleanly replaces a
prior load.

### Check it

```bash
launchctl print gui/$(id -u)/com.task-a-llama.backup
tail -f ~/Library/Logs/task-a-llama/backup.log
```

Run it manually once to confirm the path substitutions are correct:

```bash
launchctl kickstart gui/$(id -u)/com.task-a-llama.backup
```

### Uninstall

```bash
./bin/install-launchd.sh --uninstall
```

### Manual install (fallback)

If you want to do it by hand:

```bash
mkdir -p ~/Library/Logs/task-a-llama ~/Library/LaunchAgents
sed \
  -e "s#__BIN_DIR__#$PWD/bin#g" \
  -e "s#__LOG_DIR__#$HOME/Library/Logs/task-a-llama#g" \
  bin/launchd/com.task-a-llama.backup.plist \
  > ~/Library/LaunchAgents/com.task-a-llama.backup.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.task-a-llama.backup.plist
```

### Why no `--push` in the LaunchAgent

Pushing to a private Git remote from `launchd` needs the SSH agent socket
available in the `launchd` environment, which is fiddly on macOS. The
template commits but doesn't push, and you run `git -C <data_repo> push`
from a shell periodically (or not at all - commits accumulate locally and
serve as offline history).

If you really want automated push: load the SSH agent socket into `launchd`
via a separate login plist and add `--push` to the `ProgramArguments`.

## Restoring

The stack is stopped automatically during restore; you don't need to stop
it first.

### From a binary snapshot (preferred)

```bash
./bin/restore.sh binary ~/backups/task-a-llama/task-a-llama-2026-04-24-040000.tgz
```

Restores both the database and the attachments. Prompts for confirmation
before overwriting.

### From a SQL dump

```bash
./bin/restore.sh sql ~/code/task-a-llama-pasture/tasks.sql
```

Restores the database only. Attachments in `runtime_dir/files/` are left
alone. Use this when the binary snapshots are gone and you only have the
Git-tracked SQL dump.

### Credentials after a nuke + restore

When you nuke and then run bootstrap before restoring, bootstrap creates a
fresh account and prints a new password. That account exists only in the
empty database bootstrap started with -- as soon as restore replaces the
database with your backup, that account is gone.

After a restore you need your **pre-nuke credentials**, not the ones bootstrap
just printed. If you no longer have them, reset the password via the Vikunja
CLI (the stack must be running):

```bash
# Find the user ID
docker exec vikunja /app/vikunja/vikunja user list

# Generate a new password and reset it directly (no email required)
new_pass="$(openssl rand -base64 18)"
docker exec vikunja /app/vikunja/vikunja user reset-password \
  --direct \
  --password "$new_pass" \
  <user-id>
echo "New password: $new_pass"
```

Save the new password in your password manager.

## Full disaster recovery from scratch

You lost everything on the local machine. You have:

- A clone of the framework repo (or can re-clone it)
- A clone of the data repo (`task-a-llama-pasture`) with the committed SQL dump

Steps:

```bash
# 1. Clone the framework
git clone <framework-url> ~/code/task-a-llama
cd ~/code/task-a-llama

# 2. Clone the data repo
git clone <data-repo-url> ~/code/task-a-llama-pasture

# 3. Configure
cp config.example.yml config.yml
$EDITOR config.yml       # confirm paths

# 4. Bootstrap and bring up a clean instance
./bin/bootstrap.sh --up

# 5. Wait for Vikunja to initialize the empty DB, then down the stack
./bin/down.sh

# 6. Restore from the SQL dump
./bin/restore.sh sql ~/code/task-a-llama-pasture/tasks.sql
```

At step 6 the restore script starts the stack back up for you. Log in with
your pre-disaster credentials (not the ones bootstrap printed in step 4 --
those were for the empty database and are now superseded by the restore).
If you don't have them, see "Credentials after a nuke + restore" above.
All tasks, projects, and labels come back.

Attachments (if you had any) are not recoverable from the SQL dump alone -
they live only in binary snapshots. For a TODO workflow this is usually
fine; if you rely on attachments, keep a binary snapshot off-site
(e.g. rsync the latest `.tgz` to a separate machine).

## Troubleshooting

**`database not found`** - the stack has never been bootstrapped, or
`runtime_dir` in `config.yml` points somewhere unexpected. Confirm:

```bash
yq '.runtime_dir' config.yml
ls "$(yq -r '.runtime_dir' config.yml | sed "s|^~|$HOME|")/db/"
```

**`--commit requires a git repo at ...`** - clone the data repo to the
configured path, or run `git init` there if you're deferring the remote
setup.

**Pruned too aggressively** - increase `backup.retention_days` in
`config.yml`. The prune only touches files matching `task-a-llama-*.tgz`;
anything else parked in `binary_dir` is untouched.

**Wrong username or password after restore** - if you restored a backup after
a nuke + bootstrap cycle, the credentials bootstrap printed are for the
empty database and no longer apply. Use your pre-nuke credentials, or reset
via the CLI (see "Credentials after a nuke + restore" above).

**LaunchAgent silently does nothing** - `launchctl print gui/$(id -u)/com.task-a-llama.backup`
shows the last run's exit code. Check `~/Library/Logs/task-a-llama/backup.err`.
Most common cause: path substitutions (`__BIN_DIR__`, `__LOG_DIR__`) were
not applied when the template was copied.
