---
name: session-closeout
description: Leave things so the next session can trust what it finds. Take stock of what this session touched, bring each thing to done, gone or handed over, and pass on what was learned. Use it when the operator says "close out", "close this session", "wrap up" or "/session-closeout", and at any pause where work is being set down — before a break, before handing work back, before a long task.
disable-model-invocation: false
---

# session-closeout

The next session starts from what this one leaves. It should be able to trust what it finds and begin, with nothing to wonder about. Four things make that so:

- **Only one.** Nothing exists twice. What was replaced is gone.
- **True.** What is written matches the system.
- **Finished, or says so.** Everything this session touched is done, removed, or handed over with a note.
- **Learned once.** What this session found out is left where the next one will meet it.

## 1. Take stock

List what this session touched or created. You are the only one who knows. Think across everything the work reached: repositories and branches, pull requests, tickets, pages and documents, files and folders, running jobs, and anything you told the operator you would do. Those are examples; the list is whatever this session actually did.

## 2. Bring each thing to one of three states

| State | It means |
| --- | --- |
| **Done** | Finished and in its home: merged, closed, true. A clone is back on its default branch and up to date |
| **Gone** | Removed. This includes whatever a change replaced, and anything made only to get the work done |
| **Handed over** | Still open, with a note where the next session will find it, saying what it is, where it stands, what you would do next, and whose it is. For a piece of work, the note is a comment on its ticket |

Finish what is quick to finish. Remove what has no further use. Hand over the rest. Something you did not make stays as it is, and the operator hears about it.

## 3. Pass on what was learned

If the work changed what is true of a project, or you tripped on something, decided something, or found something that behaves oddly, run `/project-docs update`. It puts each thing where the next session will meet it.

## 4. Tell the operator

One short closing note: what is handed over and where its note is, or that nothing is left open. Include anything you found that was not yours.
