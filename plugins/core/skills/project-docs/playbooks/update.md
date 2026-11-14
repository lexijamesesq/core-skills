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
| A session that would have to work around the same thing: something about the system that behaves oddly and will stay that way for now | A row in Known issues, if it earns one (below) |
| A session that might undo or redo a choice: what was decided, why, and what was rejected | A row in Decisions, if it earns one (below) |
| A session reading one piece of code: why it is the way it is | A comment at that code |

Most finished work comes to one changed line on an area page, sometimes with a knowledge document or a comment. Some comes to nothing, because the ticket and the code already hold all of it.

If you got something wrong along the way because nothing warned you, leave the warning for the next session: a Boundary on the area page, a row in Known issues, or a comment at the code.

## What earns a row

Both databases are read by every session that works in the area, so a row has to be worth each of those reads. Most finished work adds none.

**A decision earns a row when all of these hold.**

- A later session, working on something else, could plausibly undo it or decide it again.
- There was a real alternative, and you can say what was rejected. If the Rejected field would be empty, it was not a decision.
- It is about the project, and will still matter when the work it came from is forgotten. A choice that only shaped one piece of work stays on its ticket.

Look first for a row it repeats or replaces. Decisions are made in the session, by you or with the operator; the row records the outcome and needs no further approval.

**A known issue earns a row when it is a standing condition**: something a session has to work around for the foreseeable future, whether or not anyone means to change it. An upstream limitation, an accepted quirk and a fault whose fix is not close are all standing conditions. A fault that this work or the next is fixing is a ticket and gets no row.

A row is not a copy of a ticket. The row says what happens and what to do about it today. A ticket, where there is one, says how it gets fixed, and the row links to it.

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

Agree first before adding or removing an area, or changing a rule on the overview or a boundary on an area. When you're done, tell the operator what you changed and where.
