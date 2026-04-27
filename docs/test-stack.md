# Test stack: isolated second Vikunja for skill development

## Why

The `/tal` skill targets a real Vikunja instance. Once you're using it in
anger for actual task management, you don't want regression testing,
exploratory work, or "what happens if I delete this?" experiments
contaminating the gold-copy data.

The framework supports a fully isolated second stack:

- Production: `~/vikunja/`, container `vikunja`, port 3456
- Test:       `~/vikunja-test/`, container `vikunja-test`, port 4567

Both stacks share the same `docker-compose.yml`, `.env.example`, and
lifecycle scripts -- the test instance is a parameterised invocation,
not a fork.

## Setup

From the framework repo root, with Docker running:

```bash
# 1. Bootstrap the test runtime_dir, .env (port 4567), JWT, and stack.
./bin/bootstrap.sh test --up

# Bootstrap will spin up the container, wait for readiness, and create
# the initial admin account on the test instance. SAVE the printed
# credentials -- they are different from production.

# 2. Open the test UI to create an API token.
open http://localhost:4567

# 3. Capture the token into the test .env.
./bin/first-run.sh test
```

Both stacks now run side-by-side. You can verify with:

```bash
docker ps --filter "label=com.centurylinklabs.watchtower.enable=true"
# Should show: vikunja (port 3456), vikunja-test (port 4567)
```

## Switching the /tal skill

The skill reads `~/.config/task-a-llama/active-mode` on every turn.
Three ways to flip:

1. **Tell the skill**: "switch to test mode" / "switch to production
   mode". The skill verifies the target stack is reachable, writes the
   mode file, and confirms.

2. **Direct CLI**: `./bin/mode.sh test` or `./bin/mode.sh production`.
   Useful from a non-Claude shell or in scripts.

3. **Read current mode**: `./bin/mode.sh` (no args) prints the active
   mode without changing it.

When in test mode, every `/tal` response begins with a banner:

    [TEST MODE - http://localhost:4567]

This is mandatory and intentional -- it makes accidental cross-targeting
impossible to miss.

## Lifecycle commands

Every lifecycle script accepts an optional `[production|test]` argument,
defaulting to `production`:

```bash
./bin/up.sh test          # start the test stack
./bin/down.sh test        # stop without destroying
./bin/nuke.sh test        # destroy data (test-only -- production unaffected)
./bin/backup.sh test      # rare; test data is normally disposable
./bin/first-run.sh test   # capture/refresh the test API token
```

Production commands are unchanged: `./bin/up.sh` etc.

## Resetting the test stack

Test data is disposable by definition. To start fresh:

```bash
./bin/nuke.sh test
./bin/bootstrap.sh test --up
./bin/first-run.sh test
```

This destroys the test database, attachments, .env, and the compose
symlink. Production is untouched.

## What is NOT split

- **Backups**: production runs the LaunchAgent backup; the test stack
  does not. Test backups via `./bin/backup.sh test` are supported but
  unusual.
- **Companion repos**: `task-a-llama-skills`, `task-a-llama-overlay`,
  and the data repo are shared -- skills are global to the Claude Code
  installation.
- **Mode file**: `~/.config/task-a-llama/active-mode` is global; both
  stacks share the single switch state.

## Checking what's where

```bash
./bin/mode.sh                                       # current /tal target
docker ps --format 'table {{.Names}}\t{{.Ports}}'  # what's running
ls -la ~/vikunja/ ~/vikunja-test/ 2>/dev/null      # data directories
```
