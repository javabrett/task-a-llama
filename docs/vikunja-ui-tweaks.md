# Vikunja UI tweaks

Browser-level CSS overrides for the Vikunja frontend, applied via the
[Stylish](https://add0n.com/stylus.html) extension (or Stylus, its actively
maintained fork). Install one of these extensions, create a new style scoped
to `localhost:3456`, and paste the relevant rules.

## Hide the project-scoped task index

**Problem:** The task detail view shows a `#10`-style heading above the task
title. This is the per-project sequential index, not the global API task ID
(the one in the URL). For a single-user setup where all task references go
through the URL or the `/tal` skill (both of which use the global ID), the
project index is misleading noise.

**Background:** Vikunja computes the identifier from the project's optional
prefix setting plus the task's per-project index (e.g. `TAL-10`). If no
prefix is set the raw index shows as `#10`. There is no API endpoint to look
up tasks by this identifier in released versions; the global numeric ID in
the URL is the authoritative reference. A `GET /projects/{id}/tasks/by-index/{index}`
endpoint landed in Vikunja `main` on 2026-04-11 but is not yet released.

**Fix:**

```css
/* Hide the per-project task index (#10 / TAL-10) from the task detail heading.
   The global task ID remains accessible via the URL (/tasks/{id}). */
.title.task-id {
    display: none;
}
```

Scope this style to `http://localhost:3456/*` in Stylish/Stylus so it only
applies to your local Vikunja instance.

**What you lose:** The `.task-id` element is also a button that copies the
task URL to the clipboard on click. Hiding it removes that affordance. The
URL bar is an equivalent copy source.
