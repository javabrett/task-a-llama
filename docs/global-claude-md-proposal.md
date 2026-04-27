# Proposed addition to `~/.claude/CLAUDE.md`

**Status: proposal, NOT installed.** This document drafts a small
section to add to your global `~/.claude/CLAUDE.md` so that Claude
Code knows about the `task-a-llama` framework and uses the `/tal`
skill correctly. Read it, edit to taste, then paste into your
global file by hand.

The framework intentionally does not modify `~/.claude/CLAUDE.md`
on your behalf: that file is your personal config space, often
stow-managed, and an automated edit there would be intrusive.

## Proposed section

```markdown
## task-a-llama

Self-hosted Vikunja task manager runs as part of the `task-a-llama`
framework at `~/src/task-a-llama` (framework) with runtime data at
`~/vikunja/` (DB, attachments, .env). Companion repos:
`~/src/task-a-llama-skills` (public skills) and
`~/src/task-a-llama-pasture` (SQL dump history).

### When to use the `/tal` skill

For any Vikunja work - capturing TODOs, listing tasks, marking done,
adding labels - prefer the `/tal` skill over hand-rolled curl. The
skill enforces the project-mapping conventions and the dry-run-
before-mutation safety contract documented in
`~/src/task-a-llama-skills/adapters/claude-code/.claude/skills/tal/SKILL.md`.

The skill matches on natural-language phrases ("add to vikunja",
"capture todos", "what's open for", "mark X done"); the user
typically does not need to type `/tal` literally.

### Working-directory to project mapping

The skill maps `$PWD` to a Vikunja project. Override the default
auto-create behaviour by writing a numeric project id (or exact
project title) into `$PWD/.task-a-llama/project`. The convention
is single-user gitignored; `.task-a-llama/` is in
`~/.gitignore_global`. Users who want team-shared mappings can opt
in by committing the file.

### API and ad-hoc debugging

API token lives in `~/vikunja/.env` as `VIKUNJA_API_TOKEN=tk_...`.
Base URL: `http://localhost:3456/api/v1`. The skill's
`references/endpoints.md` carries the endpoint cheatsheet.

For one-off debugging:

\`\`\`bash
TOKEN=$(grep '^VIKUNJA_API_TOKEN=' ~/vikunja/.env | cut -d= -f2-)
curl -sf -H "Authorization: Bearer $TOKEN" http://localhost:3456/api/v1/projects | jq
\`\`\`

### Interaction with per-repo `CLAUDE.md`

This section is global guidance. Per-repo `CLAUDE.md` files take
precedence when their advice conflicts (e.g. a repo that pins to a
specific Vikunja project should say so in its own `CLAUDE.md`, not
expect the global file to know about it).
```

## Suggested companion change to `~/.gitignore_global`

If you don't already have a global gitignore configured, see
`git config --global core.excludesfile`. Add the line:

```
.task-a-llama/
```

This keeps the per-directory project pointer file out of any repo
by default. Opt in to committing it on a per-repo basis with
`git add -f .task-a-llama/project`.

## Why no automated install

Three reasons:

1. `~/.claude/CLAUDE.md` often lives under stow management; an
   automated insert would conflict with the source dotfile.
2. The right placement is opinionated (top? bottom? alongside other
   project-specific blocks?) and depends on your existing structure.
3. The framework deliberately stays AI-runtime-agnostic at the
   infrastructure layer - automated edits to a Claude Code config
   file would violate that boundary.
