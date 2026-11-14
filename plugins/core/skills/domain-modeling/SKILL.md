---
name: domain-modeling
description: >
  Build and sharpen a project's domain model — pin down terminology,
  challenge fuzzy language, record architectural decisions. Works for
  engineering, strategy, research, and design domains.
---

# Domain Modeling

<!-- Adapted from Matt Pocock's domain-modeling skill (MIT): https://github.com/mattpocock/skills. Estate mutation: the project's documentation replaces repo-level CONTEXT.md; cross-reference generalized beyond code. -->

Actively build and sharpen the project's domain model as you design. This is the *active* discipline — challenging terms, inventing edge-case scenarios, and writing the glossary and decisions down the moment they crystallise. (Merely *reading* a domain glossary for vocabulary is not this skill — that's a one-line habit any skill can do. This skill is for when you're changing the model, not just consuming it.)

## Where the model is kept

The glossary and the decisions live in the project's documentation, which `/project-docs` describes. A glossary is a knowledge document of type Reference, kept current (Update `replace`). A decision is a row in the project's Decisions database. Write both through `/project-docs update`.

Most projects have a single domain context and one glossary. A project that spans several bounded contexts keeps a context map, a knowledge document that lists them and how they relate, and one glossary for each.

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with existing knowledge

When the user states how something works, check whether the existing record agrees. For engineering work, check the code. For strategy, research, or design, check the project's existing knowledge documents. If you find a contradiction, surface it: "Your glossary says X, but the knowledge doc on this topic says Y — which is current?"

### Update the glossary inline

When a term is resolved, update the glossary right there. Don't batch these up — capture them as they happen. Each entry is three parts: the **term** (bolded), a one-or-two-sentence **definition** (what it IS, not what it does), and an ***Avoid*** list of synonyms ruled out. The glossary itself is a knowledge document in the project's Knowledge database.

The glossary should be totally devoid of implementation details. Do not treat it as a spec, a scratch pad, or a repository for implementation decisions. It is a glossary and nothing else.

### Offer decisions sparingly

Only offer to record a decision when all three are true:

1. **Hard to reverse** — the cost of changing your mind later is meaningful
2. **Surprising without context** — a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons

If any of the three is missing, skip it. On the operator's yes, the decision becomes a row in the project's Decisions database.
