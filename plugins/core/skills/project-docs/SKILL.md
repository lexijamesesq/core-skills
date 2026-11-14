---
name: project-docs
description: How a project's documentation in Notion is meant to be used and kept — the frame, plus a playbook for each moment. Load it when you start work on a project and need context for your task (onboard), when work you finished changed what is true and the docs need to follow (update), or when a project needs its documentation created (setup). Triggers on "/project-docs onboard", "/project-docs update", "/project-docs setup", "orient me on <project>", "update the project docs". Projects only.
disable-model-invocation: false
---

# project-docs

## The frame

A project's documentation exists to give a fresh session enough context to work on the project in front of it. Enough, and no more: it is not a store of everything known about the project.

### Where a project's knowledge lives

The documentation is one of three places, and each holds its own kind.

| Where | What it holds |
| --- | --- |
| **The code**, and comments in it | What the system does, exactly. A comment says why a piece of code is the way it is |
| **Linear** | The work: what is planned, under way, tried, decided along the way, and proven |
| **The documentation**, in Notion | What the project is, what is true of it now, and how to work in it. Three altitudes: |
| — Overview, the project's page | The whole project: what it is, how work moves through it, which area a kind of task belongs to |
| — Area, a sub-page | One part: what is true of it today, how to work there, where its detail is |
| — Knowledge document, a row in the Knowledge database | One subject: design and reasons, decisions, research, procedures, records |

Each thing is kept in one of these and pointed to from the others.

### How a session uses it

A session takes a path through the documentation. The task the operator gave decides the path: the overview, then the area the task belongs to, then the documents that task needs, and from there to the ticket and the code. Two sessions with different tasks read different pages, and each arrives with what it needs and room left to work.

### What keeps it good

The documentation is as good as the last session left it. It stays good because the sessions that use it also keep it: when your work changes what is true of the project, the page that describes it changes in the same piece of work. And it stays usable because each thing sits at the altitude of the sessions that need it: on the overview if every session does, on an area if every session working there does, in a knowledge document if only some do.

## Where a project's pages are

The instruction file in the folder you started in (`CLAUDE.md` or `AGENTS.md`) names them in its front matter:

```yaml
notion_project: <the project's page — the overview>
notion_knowledge: <the project's Knowledge database>
```

Reach them with the Notion connector. If the file has no pointers, tell the operator.

## Playbooks

Load the one for what you need now.

| Your need | Playbook |
| --- | --- |
| Context for the task you've been given | `playbooks/onboard.md` |
| The docs should change, because the project did | `playbooks/update.md` |
| The project needs its documentation created | `playbooks/setup.md` |
