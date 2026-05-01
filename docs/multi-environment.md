# Multiple environments (slugs)

The framework supports unlimited named environment slugs. Common setups:

- `prod` (local Docker) + `test` (local Docker)
- `prod` (local Docker) + `cloud1` (Vikunja Cloud)
- Multiple Cloud accounts, each as a separate slug

Each slug has its own URL, API token, and (for local stacks) Docker runtime
directory. The active slug is stored in `~/.config/task-a-llama/active`.

## Why you want a test slug

Once you use `/tal` for real task management you do not want regression
testing or exploratory "what happens if I delete this?" experiments
contaminating your production data. A separate slug gives you a fully
isolated Vikunja instance with no data shared.

## Adding a local slug

```bash
# Bootstrap creates ~/vikunja-test/ and ~/.config/task-a-llama/test/env.
./bin/bootstrap.sh test

# Bring it up.
./bin/up.sh test

# Open the test UI to create an API token.
open http://localhost:4567

# Capture the token.
./bin/first-run.sh test
```

Both slugs run concurrently. Verify:

```bash
docker ps --filter "label=com.centurylinklabs.watchtower.enable=true"
# vikunja-prod (port 3456), vikunja-test (port 4567)
```

## Adding a Vikunja Cloud slug

Cloud slugs have no local Docker runtime - the TAL-side env file is the
only artefact.

```bash
mkdir -p ~/.config/task-a-llama/cloud1

cat > ~/.config/task-a-llama/cloud1/env <<'EOF'
VIKUNJA_BASE_URL=https://app.vikunja.cloud/api/v1
VIKUNJA_API_TOKEN=create_in_vikunja_ui_after_first_login
EOF

# Capture the token (opens the Cloud API tokens UI).
./bin/first-run.sh cloud1

# Switch to cloud1 and verify reachability.
./bin/mode.sh cloud1
```

`bin/up.sh cloud1`, `bin/down.sh cloud1`, etc. refuse with a clear message
for cloud slugs - they are local-only operations.

## Switching the active slug

Three ways:

1. **Tell the skill**: "switch to test" / "switch to prod" / "tal mode".
   The skill verifies reachability, writes the active file, and confirms.

2. **Direct CLI**: `./bin/mode.sh test`. Verifies reachability first.
   `./bin/mode.sh` (no args) prints the current slug without switching.

3. **Write the file directly** (no reachability check):
   ```bash
   echo "test" > ~/.config/task-a-llama/active
   ```

Every `/tal` response is prefixed `[<slug>]`, so the active environment is
always visible.

## Lifecycle commands

Every lifecycle script accepts an optional `[<slug>]` argument, defaulting
to the active slug:

```bash
./bin/up.sh test          # start the test stack
./bin/down.sh test        # stop without destroying data
./bin/nuke.sh test        # destroy data (test slug unaffected from prod)
./bin/backup.sh test      # test backups are rare; test data is disposable
./bin/first-run.sh test   # capture / refresh the test API token
```

## Resetting a local slug

Test data is disposable:

```bash
./bin/nuke.sh test
./bin/bootstrap.sh test --up
./bin/first-run.sh test
```

This destroys the test database, attachments, Docker .env, and the
compose symlink. The prod slug is untouched.

## What is NOT split between slugs

- **Companion repos**: `task-a-llama-skills`, `task-a-llama-overlay`, and
  the data repo are shared - skills are global to the Claude Code session.
- **Active file**: `~/.config/task-a-llama/active` is global - it is the
  selector, so it has to be unscoped.

## Environment-scoped state rule

Each slug has its own isolated Vikunja database. Any client-side file that
holds slug-specific values (numeric IDs, tokens, base URLs) must be inside
a slug-scoped path:

- `~/.config/task-a-llama/<slug>/env` - URL + token
- `~/vikunja-<slug>/.env` - Docker-side secrets (local stacks only)
- `~/.config/task-a-llama/<slug>/overlay.yml` - per-slug overlay

Project bindings live inside Vikunja project descriptions (the `tal-meta`
block), which are naturally environment-scoped because each slug has its
own database. User repos remain tal-unaware.

## Checking what is where

```bash
./bin/mode.sh                                         # current /tal target
docker ps --format 'table {{.Names}}\t{{.Ports}}'    # what is running
ls ~/.config/task-a-llama/                           # configured slugs
```
