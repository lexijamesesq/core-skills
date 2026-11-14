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

Create documents lazily — only when you have something to write. If no glossary exists, create one when the first term is resolved.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in the domain glossary, call it out immediately. "Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account' — do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with existing knowledge

When the user states how something works, check whether the existing record agrees. For engineering work, check the code. For strategy, research, or design, check the project's existing knowledge documents. If you find a contradiction, surface it: "Your glossary says X, but the knowledge doc on this topic says Y — which is current?"

### Update the glossary inline

When a term is resolved, update the glossary right there. Don't batch these up — capture them as they happen. Each entry is three parts: the **term** (bolded), a one-or-two-sentence **definition** (what it IS, not what it does), and an ***Avoid*** list of synonyms ruled out. The glossary itself is a knowledge document in the project's Knowledge database.

The glossary should be totally devoid of implementation details. Do not treat it as a spec, a scratch pad, or a repository for implementation decisions. It is a glossary and nothing else.

### Offer decisions sparingly

Offer to record a decision only when it passes the test in `/project-docs update`, under "What earns a row". When it does, it becomes a row in the project's Decisions database, added through that playbook.
