# Playbook: read

Parse a project's `CLAUDE.md` and return structured Project State + routing fields.

## Input

- `project_root` — absolute path to project folder, OR `"cwd"`, OR project name (resolved per SKILL.md › Project resolution: `{projects_root}/<name>`, `{workspace_root}/System`, or `{projects_root}/Agents/<name>`).

## Protocol

1. **Resolve** `project_root` per the navigator's cross-cutting "Project resolution" rule. Fail with clear error if no `CLAUDE.md` exists.

2. **Read** `<project_root>/CLAUDE.md`.

3. **Parse frontmatter** (via `Read`):
   - `description` → `description`
   - `status` → `status`
   - `updated` → `last_updated`
   - `linear_project_id` → `linear_project_id` (UUID). **Required**; if absent, surface as data error.
   - `linear_url` → `linear_project_url`
   - `knowledge_intake` → `knowledge_intake` (boolean; absent = false)
   - `build_home` → `build_homes` (list of absolute paths to this project's repo(s) outside the vault; absent = empty list). Replaces the retired `## Deliverable Repos` body section — see `System/project-claude-template.md`.

4. **Parse the body** for session-relevant fields:
   - `## Re-entry Cue` → `re_entry_cue` (the prose below the heading; may be absent or say "No work in progress" — both mean null)

5. **Build the structured return.**

## Output

```yaml
project_root: <abs-path>
description: <string or null>
status: <string or null>
last_updated: <YYYY-MM-DD or null>
re_entry_cue: <string or null>
linear_project_id: <UUID or null>
linear_project_url: <URL or null>
knowledge_intake: <bool>
build_homes: <list of abs-paths, possibly empty>
```

## Fields removed from prior version

These fields are no longer parsed from CLAUDE.md. They were session-level memory that now lives in Linear:

- `current_state` — read from Linear Project Updates via `/session-start`
- `waiting_for` — read from Linear issue states via `/session-start`
- `decisions_needed` — read from Linear issue states via `/session-start`
- `capture_note_path` — retired

## Failure modes (surface to caller; do not paper over)

- **No CLAUDE.md at resolved path:** return null with error string `"No CLAUDE.md at <resolved-path>"`.
- **Missing `linear_project_id` in frontmatter:** surface as data error. Pre-cutoff fallback to `linear_getProjects` name-match is RETIRED.
- **Missing `description` in frontmatter:** surface as warning — the project is invisible to routing until a description is added.

## Parser notes

- Take all structured fields from the frontmatter block. Parse the body only for the Re-entry Cue.
- The Re-entry Cue heading may be `## Re-entry Cue` or `### Re-entry Cue` (template uses `##`; legacy files may use `###`). Accept either.
