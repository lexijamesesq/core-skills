# Playbook: setup

A project needs its documentation: a new project, or an existing one being brought into this shape. The operator tells you the project, where its Notion page is or should go, and which folder sessions start in. Use the map in the direction of placing, for the whole project at once.

The aim is an overview a fresh session can read in a minute and know where to go next.

## Look first

Fetch the project page and see what is under it. Open enough to know what each page is. Everything stays; pages outside this shape are left where they are and reported to the operator.

## The Knowledge database

One per project, on the project page, named `Knowledge`, with these fields, spelled this way in every project:

| Field | Type | Values |
| --- | --- | --- |
| Name | title | |
| Type | select | Methods, Reference, Research, Records |
| Update | select | replace, append, never |
| Updated | date | when the content was last true |
| Description | text | one line: what it is and when to read it |
| Related | relation | to this same database (add it once the database exists) |

Move the project's existing documents into it and fill every field. For Update: a dated record is `never`, a log is `append`, anything else is `replace`. Write each Description for a session deciding whether to open the document.

## Known issues and Decisions

Two more databases on the project page, in every project, with these fields.

**Known issues**: one row for each thing that is wrong or surprising about the system as it is now.

| Field | Type | Values |
| --- | --- | --- |
| Name | title | what happens, as a short statement |
| Area | select | `Project-wide`, and one option per area |
| What to do | text | how to work around it or avoid it |
| Ticket | URL | the ticket for fixing it, if there is one |

**Decisions**: one row for each decision a later session would otherwise undo or redo.

| Field | Type | Values |
| --- | --- | --- |
| Name | title | the decision, as a sentence |
| Area | select | `Project-wide`, and one option per area |
| Decided | date | when |
| Why | text | the reason, in a line or two |
| Rejected | text | what was considered and not chosen |
| Source | URL | the ticket or map where it was decided |
| Replaces | relation | to this same database (add it once the database exists) |

A row's page body holds the longer reasoning when a decision needs it. An existing list of known issues, or existing decision documents, become rows.

## Areas

A project has areas when a session could work in one part without needing the others. Many projects are one part, and go from the overview straight to the documents. Name an area for what a task there would be about. Agree the list with the operator.

## The overview

On the project page itself, in this order:

- **What the project is**, in a paragraph, so a session knows it is in the right place.
- **How work moves**: the few steps from a tracked piece of work to a change in the world.
- **Areas**: a table. Each row is an area's name, linked, and "go here when…" written from the task's side.
- **Where things live**: the repositories, the three databases (Knowledge, Known issues, Decisions), where work is tracked.
- **Rules** that hold everywhere in the project.

Try the area table on three tasks someone might bring, and adjust the wording until each lands on one row.

## Each area page

- **One line** saying what this part of the project is.
- **State**: short facts about what exists, works, and is missing, each linked to the document with the detail.
- **Artifacts**: the knowledge documents this area owns, and where its code or configuration is.
- **Boundaries**: how to work here, as one to three instructions. The project's history is where to find them: the operator's corrections, and lessons recorded in the documents.
- **Chain**: links up to the overview and across to neighbouring areas.

Take State from the documents and from what you can check in the code or the running system.

## Pointers

Add to the front matter of the instruction file in the folder sessions start in:

```yaml
notion_project: <URL of the project's page>
notion_knowledge: <the Knowledge database's data-source URL>
```

and a line in its body pointing a session to `/project-docs onboard`. These replace any pointer to an earlier location. When the file is in a repository, the change goes through that repository's review.

## Walk it

Pick a task the project really has and follow the `onboard` playbook from the pointers. Adjust the pages until the path gets you there. Then tell the operator what you built, what you left in place outside this shape, and anything you'd want checked.
