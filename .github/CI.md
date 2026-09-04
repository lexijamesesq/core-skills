# CI workflow shape

This repo follows dotty's CI shape (`.github/CI.md` there — least-privilege
`permissions:`, `concurrency:` with `cancel-in-progress`, `timeout-minutes`
on every job, SHA-pinned actions, dotty's shared gitleaks composite). This
file records the decisions that are specific to this repo — the plugin
marketplace publisher — not a duplicate of dotty's own record.

## Decisions recorded here so they aren't re-proposed without new facts

**`claude plugin validate --strict` gates every PR** (`validate-and-test`).
This repo IS a marketplace and two plugins; a manifest or plugin.json error
here breaks installation for every consumer, not just this repo's own tests.

**`drift-check` and `standalone-check` are separate questions, separate
jobs.** `drift-check` proves the packaged copies here still match dotty's
current `main` (dotty's own copies are the narrowing anchor since its
duplicate skills/agent/hooks were retired). `standalone-check` proves the
packaged copies work with dotty simply absent from the runner — the same
way an installed plugin cache is absent it on any real machine. Conflating
them would hide a plugin that only "works" because dotty happens to be
checked out alongside it.

**Release job: PR-time check, split from push-time tag+Release.**
Two jobs, not one:

- `release-check` (`pull_request`) compares each plugin's tree against its
  **highest existing tag**, not the tag matching the currently-declared
  version. Comparing against the declared-version tag would go silent
  during any window the push-time tagger is unhealthy (this repo's own
  `drift-check` can go red from an unrelated dotty commit, and while it's
  red no tag gets cut) — every PR merged in that window would see "tag
  absent" and pass freely, then land at whatever tree existed when the
  tagger recovered. Comparing against the highest tag closes that
  structurally: an untagged-but-merged version still trips the mismatch.
  Content changed with no version bump above that tag → fail loud,
  naming the plugin (receipt: `estate-hooks` shipped three distinct trees
  at version `0.2.0` within 73 minutes on 2026-09-03 — the failure this
  check exists to catch). This repo publishes two
  plugins in one job; results are collected and the job fails at the end
  if either differed, so one plugin's fail doesn't let the other's tag
  land on the wrong commit.
- `release-tag` (`push` to `main`) re-runs the same comparison against the
  *declared* version specifically and, if untagged, cuts
  `claude plugin tag --push` + a GitHub Release. Idempotent — safe to
  re-run after a cancelled or failed attempt (see
  `.github/scripts/tag-plugin-release.sh`; the tag and the Release are
  checked and created independently, so a failure between the two never
  leaves a tag with no Release).

**Branch-protection ruleset requires `release-check`, `strict`.** Before
this, work-lifecycle's ruleset required no status checks at all — the
release-check job in a PR only reported, it never blocked. Strict (the
branch must be up to date before merging) is the accepted cost: without it,
two PRs both bumping the same plugin to the same version each see "no
prior tag conflict" independently, and whichever merges second produces
exactly the post-merge failure this whole mechanism exists to prevent. The
throughput cost is real on this repo's ~20-minute `validate-and-test`
suite and its merge cadence — accepted anyway, named here rather than
silently eaten.

**Concurrency keyed on `github.sha` for non-PR events, not the shared
`github.ref` group.** GitHub's default concurrency queue holds at most one
*pending* run per group and replaces it — `cancel-in-progress: false`
alone only protects a *running* run, not one still queued behind `needs:`.
A shared push-triggered group could silently drop a version-bump's release
run in favor of a later no-bump push landing before the first run starts.
Keying on the commit SHA for `push`/`schedule` events gives every commit
its own group slot, so nothing is ever replaced; PR events still key on
`github.ref` with `cancel-in-progress: true`, since a superseding push to
the same PR should cancel the stale run as before.

**First-release baselines, cut deliberately, not accidentally:**
`work-lifecycle--v0.3.1`, `estate-hooks--v0.3.1`. Both versions already
reflect real, intentionally-set state as of this PR — no bump needed here
to produce a clean first tag.
