# Playbook: update

You finished something and the project is different now. Bring the documentation into line, so the next session starts from what is true. Use the map in the direction of placing.

## What changed about the project

From everything you did, pick out what is now true of the project that wasn't before, and what the pages say that has stopped being true. That is what an update is made of.

The rest already has its place. The account of the work, what you tried, how you proved it, is on the ticket. Exactly how it works is in the code.

## Where each thing goes

For each thing that is now true, ask which sessions need it.

| Who needs it | Where it goes |
| --- | --- |
| Every session on the project: a new area, a change in how work moves, a rule that holds everywhere | The overview |
| Every session working in one area: what exists, works or is missing there, or how to work there | That area page, under State or Boundaries |
| A session doing one particular thing: how something is designed and why, a procedure | The knowledge document on that subject, or a new one |
| A session that would meet the same odd behaviour: something wrong or surprising that this work did not fix | A row in Known issues: what happens, the area, what to do about it, and the ticket if there is one |
| A session that might undo or redo a choice: what was decided, why, and what was rejected | A row in Decisions, on the operator's yes |
| A session reading one piece of code: why it is the way it is | A comment at that code |

Most finished work comes to one changed line on an area page, sometimes with a knowledge document or a comment. Some comes to nothing, because the ticket and the code already hold all of it.

If you got something wrong along the way because nothing warned you, leave the warning for the next session: a Boundary on the area page, a row in Known issues, or a comment at the code.

## An example

You finished adding a second storage bucket for the nightly exports. Along the way you found that the client library skips files over 2 GB and added a size check, and you verified three nights of exports.

- Exports now go to two buckets. Every session working in that area needs this. The area's State line "Exports run nightly" becomes "Exports run nightly, to two buckets."
- Why the size check exists. A session reading that code needs it. A comment at the check.
- The three nights of verification and the order you did things in are on the ticket. The bucket's name is in the code.

## Making the change

Read the page as it is now. Find the line that describes what changed and rewrite it, so the page states the project as it is today. A State line is a short fact, with a link to the document that has the detail.

In a knowledge document, follow its Update value: `replace` is rewritten in place, `append` takes a new entry below the others, and `never` stays as it is while you write a new document and relate the two. Give a new document every field, and link it from the area it belongs to. Set Updated to today when you know the whole document is true.

A row in Known issues is removed when the issue is fixed. A row in Decisions is never edited: when a decision is reversed, add a new row and name the one it replaces.

If the same fact appears at another altitude, such as a row of the overview's area table, bring it into line too. Then read back what you wrote.

## Decisions from a map

While a map is being worked, its decisions are recorded on the map in Linear. When the map closes, read that record and bring over the decisions a session outside the map would need. Write each one for a reader who never saw the map, and give the map as its source.

## With the operator

Agree first before adding or removing an area, changing a rule on the overview or a boundary on an area, or adding a row to Decisions. When you're done, tell the operator what you changed and where.
