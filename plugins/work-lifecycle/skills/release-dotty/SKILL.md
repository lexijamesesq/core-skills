---
name: release-dotty
description: Cut dotty's own calendar-versioned release and bump every consumer's pin to it, as one local, operator-invoked act. Triggers on "/release-dotty", "release dotty", "cut a dotty release", or "bump consumers to the new dotty tag".
---

# release-dotty

The pre-commit channel's release step: dotty's exported hooks (`.pre-commit-hooks.yaml`, `git-hooks/**`) have no automated release path today, and neither do the repos that pin them. This skill closes both in one synchronous, operator-invoked act — never hosted CI, because a hosted runner's token can't open PRs in other repos and the estate's real credentials (`gh` auth, the SA SSH key) are local by design.

## Intent

**Objective.** After a merge to dotty `main` that changes an export, cut one date-based tag by a written, deterministic sequence rule, then open a bump PR in every repo whose `.pre-commit-config.yaml` pins dotty's exports — enumerated at run time, never a fixed list.

**Decision authority.** Autonomous: computing the tag, running the refuse checks, discovering consumers. Escalate: the consumer bump PRs touch every consumer's gitleaks hook chain — operator approval before invoking this skill for real, not just before opening the PRs.

**Stop rules.** Refuses rather than guesses: a dirty or off-`main` dotty checkout, a same-day tag whose existing suffixes don't fit the scheme, a computed tag that already exists on origin (a race, or a hand-cut tag not yet fetched). Never invents a tag form.

## Trigger handling

`/release-dotty <dotty-checkout-path>` (`--dry-run` prints every decision — the tag to cut or skip, every consumer found, whether each needs a bump — without pushing a tag, cutting a Release, or touching any consumer repo). Always run `--dry-run` first and show the operator what it found before the real invocation.

## The mechanism

1. **Preconditions** — refuse unless the dotty checkout is clean, on `main`, and matches `origin/main`.
2. **Re-entry** — if `HEAD` already carries a date-based tag (a prior run cut the tag but didn't finish), skip straight to the bump phase for consumers still lagging it. The Release itself is still checked and cut independently of the tag either way (`gh release view || gh release create`) — a failure between the two must never leave a tag with no Release.
3. **Due check** — if a tag already exists and no export changed since it, exit cleanly: nothing to release.
4. **Tag computation** — first tag of a UTC day is `vYYYY.MM.DD`; later ones append `-N`, N the next integer (compared numerically) after the highest existing suffix for that date, bare tag counting as `-1`. Refuses on an already-existing computed tag (checked against origin, not local state — a local cache can be stale) or a same-day tag that doesn't fit the scheme.
5. **Consumer discovery** — grep `~/bin`, `~/Agents`, `~/Repos` for `.pre-commit-config.yaml` pinning `https://github.com/lexijamesesq/dotty`, deduplicated by resolved remote URL (a worktree of an already-found repo doesn't double-count). hazel's `deploy` branch is excluded by name — it follows `dev` by the operator's own deploy, never a bump PR.
6. **Bump** — for each consumer not already at the new tag: branch from a fresh fetch of the remote's default branch (never a stale local checkout), `pre-commit autoupdate --repo` scoped to dotty only (a consumer's other pins — `pre-commit-hooks`, `shellcheck-py` — stay untouched), one open PR per consumer updated in place on a fixed branch name (`dotty-bump`), not a new PR each run.

## What this skill does NOT do

- Does NOT run in CI — see `work-lifecycle`'s `CI.md` for why the plugin channel is hosted and this one isn't.
- Does NOT decide *whether* a release is due beyond the mechanical export-diff check — an operator or `/publish` merging a dotty PR is what makes this skill worth invoking, not something this skill watches for.
- Does NOT touch a consumer's other pre-commit hook pins, or open a second PR while one is already open on the fixed branch.

## References

- `scripts/release-dotty.sh` — the entire mechanism; read it before trusting a change to this skill.
- `../publish/playbooks/gate.md` — the plugin channel's own release design, for the shape this skill deliberately doesn't take (hosted, per-plugin, PR-gated).
