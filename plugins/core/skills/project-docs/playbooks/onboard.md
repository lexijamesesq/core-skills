# Playbook: onboard

You have a task and need context for it. Use the map in the direction of finding: take your task's path down through the documentation, then go on to the ticket and the code for what they hold. Stop when you have what the task needs.

## The path

**Overview.** Fetch the project's page and read it through. It is short. Come away with what the project is, the rules that hold everywhere in it, and the row of its area table that your task falls under. If the project has no areas, go from here to the documents.

**Area.** Fetch the area your task falls under. Its State is the current picture of that part of the project. Its Boundaries tell you how to work there. Its Artifacts tell you where the code and the documents are. If it points part of your task at a neighbouring area, take that hop as well.

**Known issues and Decisions.** Both are databases on the project's page. Query each for the rows of your area and the project-wide ones. A known issue tells you what will behave oddly and what to do about it. A decision tells you what has been settled and what was rejected, so you build on it.

**Documents.** Open the documents the area links that bear on your task. To find one it doesn't link, fetch the Knowledge database to see its fields, query it, and choose by Description. Each document's Update value says how it may be edited, which matters if your task will change it.

**The ticket.** The overview says where work is tracked. Where the work stands, what has been tried and what was decided along the way are there.

**The code.** The area's Artifacts say where it is. For exactly what the system does, read it there.

## How far to go

Let the task set the depth. A question about how the project is organised is answered at the overview. A change inside one part needs its area and usually one or two documents, then the code. Go lower when the task needs detail you don't have yet, and stop when it doesn't.

When something you find looks wrong, unused or redundant, find out why before you change it. The reason is usually one hop away: a decision, a known issue, a comment at the code, or the operator.

You have enough when you know what the project is, which part your task touches, how to work there, and where to look for the detail, the state of the work, and the code.

## When the path doesn't get you there

If you had to search, if nothing covered your task, or if what you found differs from the code or the running system, carry on from what you can verify and tell the operator what was missing or different. The `update` playbook is how the pages get brought into line.
