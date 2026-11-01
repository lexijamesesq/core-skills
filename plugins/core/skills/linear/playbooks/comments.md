# Playbook: comments

Two structured comment formats, exactly specified so agents don't improvise the shape. A plain progress comment (`createComment` with a body, ISO-date-prefixed) needs no playbook — call the MCP tool directly.

**Caller-only.** Non-CONFIRMED validator verdicts, subagent working notes, and anything a session consumes to act rather than to record return to the caller and are never posted — Linear carries receipts and answers, not working material.

## `[VALIDATION]` receipt

Posted by `` `@attack-kitty` `` on the relevant issue, and only when the verdict is CONFIRMED (any other verdict returns directly to the caller, never as a Linear comment):

```text
[VALIDATION] — {validation_type}
Verdict: CONFIRMED
Intent: {one-line human-readable conclusion}
Specifics: {what was verified — concise}
```

This is the comment the map lane's guard (`playbooks/transitions.md`) and `` `@traffic-cone` ``'s `mark_done` gate check for. A verdict of anything other than CONFIRMED never lands here.

How the `mark_done` gate reads these receipts:

- **`{validation_type}` is matched as a string.** It must equal the type the ticket's Done When names (`Validation mandate: <type>`), whichever card produced the receipt. A `deliverable-check` mandate needs a `[VALIDATION] — deliverable-check` receipt.
- **Newest wins.** The gate grades the newest `[VALIDATION]` comment that is not a ticket-close receipt. A later receipt of another type displaces an earlier matching one, so the Done When's receipt must be the newest of its kind. If something else lands after it, re-post the matching receipt.
- **A ticket with no map parent needs a second receipt.** Its first line is exactly `[VALIDATION] — ticket-close` (em-dash), posted by an instance that didn't author the Done When's receipt. It comes from `` `@attack-kitty` ``'s `ticket-close` card, in its receipt-coherence run. Ticket-close receipts are excluded from the newest-wins selection, so they can land in any order.

## `[HANDOFF]`

Posted on the worked ticket at each slice close — one per close, never batched to session end — never on the map. No re-summary of what was done; the resolution comment and closed state carry that:

- The recommended next act (top frontier ticket, or a phase transition now due) — one line.
- Carry-forward the ticket body doesn't already hold, including any **non-Linear workspace state** the next session needs: uncommitted repo changes, a branch mid-flight, a pending activation.
- Any deferred work re-homed into its owning ticket, not left here.
- When the wrap changed nothing, the **null result** stated plainly ("remaining set validated, no change") — so a skipped re-evaluation is never read as a clean one.

## What this playbook does NOT do

- Does NOT cover plain progress comments — call `mcp__linear-tactic__linear_createComment` directly.
- Does NOT decide the verdict or compose the `[HANDOFF]` content — the caller judges; this playbook fixes the shape.
