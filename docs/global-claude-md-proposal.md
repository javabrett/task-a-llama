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
framework at `~/src/task-a-llama`. Named environment slugs store runtime
data in `~/vikunja-<slug>/` (local stacks) or target Vikunja Cloud; the
active slug is in `~/.config/task-a-llama/active`. Companion repos:
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

The skill maps `$PWD` to a Vikunja project via a `tal-meta` block
embedded in the Vikunja project's description (server-side, no
per-repo files). Override the auto-discovery behaviour - or alias
several directories to one project - via
`~/.config/task-a-llama/overlay.yml` under `projects.aliases`. User
repos do not need a `.task-a-llama/` directory.

### API and ad-hoc debugging

The active slug's token and base URL live in
`~/.config/task-a-llama/<slug>/env`. The skill's
`references/endpoints.md` carries the endpoint cheatsheet.

For one-off debugging (replace `prod` with your active slug):

\`\`\`bash
SLUG=$(cat ~/.config/task-a-llama/active)
TOKEN=$(grep '^VIKUNJA_API_TOKEN=' ~/.config/task-a-llama/"$SLUG"/env | cut -d= -f2-)
BASE=$(grep '^VIKUNJA_BASE_URL=' ~/.config/task-a-llama/"$SLUG"/env | cut -d= -f2-)
curl -sf -H "Authorization: Bearer $TOKEN" "$BASE/projects" | jq
\`\`\`

### Interaction with per-repo `CLAUDE.md`

This section is global guidance. Per-repo `CLAUDE.md` files take
precedence when their advice conflicts (e.g. a repo that pins to a
specific Vikunja project should say so in its own `CLAUDE.md`, not
expect the global file to know about it).
```

## Suggested companion change to `~/.gitignore_global`

No longer needed. The framework no longer writes any per-repo
state - project bindings live inside Vikunja project descriptions.
If you previously added `.task-a-llama/` to `~/.gitignore_global`,
you can leave it there harmlessly or remove it; the framework will
not create the directory.

## Why no automated install

Three reasons:

1. `~/.claude/CLAUDE.md` often lives under stow management; an
   automated insert would conflict with the source dotfile.
2. The right placement is opinionated (top? bottom? alongside other
   project-specific blocks?) and depends on your existing structure.
3. The framework deliberately stays AI-runtime-agnostic at the
   infrastructure layer - automated edits to a Claude Code config
   file would violate that boundary.
