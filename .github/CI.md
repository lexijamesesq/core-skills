# CI workflow shape

This repo follows dotty's CI shape (`.github/CI.md` there — least-privilege
`permissions:`, `concurrency:` with `cancel-in-progress`, `timeout-minutes`
on every job, SHA-pinned actions, dotty's shared gitleaks composite). This
file records the decisions that are specific to this repo — the plugin
marketplace publisher — not a duplicate of dotty's own record.

## Decisions recorded here so they aren't re-proposed without new facts

**`claude plugin validate --strict` gates every push** (the `core-plugin-validation`
pre-push hook).
This repo IS a marketplace and three plugins; a manifest or plugin.json error
here breaks installation for every consumer, not just this repo's own tests.

**`drift-check` and `standalone-check` are separate questions, separate
checks.** `drift-check` proves the packaged copies here still match dotty's
current `main` (dotty's own copies are the narrowing anchor since its
duplicate skills/agent/hooks were retired). `standalone-check` proves the
packaged copies work with dotty simply absent from the runner — the same
way an installed plugin cache is absent it on any real machine. Conflating
them would hide a plugin that only "works" because dotty happens to be
checked out alongside it.

**Release: version check before push, split from push-time tag+Release.**
Two steps, not one:

- The `release-version` pre-push hooks (`core-version`,
  `estate-hooks-version` and `orca-hooks-version`, from dotty) compare each plugin's tree against its
  **highest existing tag**, not the tag matching the currently-declared
  version. Comparing against the declared-version tag would go silent
  during any window the push-time tagger is unhealthy — every PR merged in
  that window would see "tag absent" and pass freely, then land at
  whatever tree existed when the tagger recovered. Comparing against the highest tag closes that
  structurally: an untagged-but-merged version still trips the mismatch.
  Content changed with no version bump above that tag → fail loud,
  naming the plugin (receipt: `estate-hooks` shipped three distinct trees
  at version `0.2.0` within 73 minutes on 2026-09-03 — the failure this
  check exists to catch). This repo publishes three
  plugins, each with its own hook, so one plugin's fail doesn't let
  another's tag land on the wrong commit.
- `release-tag` (`push` to `main`, in `plugin-release.yml`) re-runs the same
  comparison against the *declared* version specifically and, if untagged, cuts
  `claude plugin tag --push` + a GitHub Release. Idempotent — safe to
  re-run after a cancelled or failed attempt (see dotty's shared
  `tag-plugin-release.sh`, invoked via `estate-plugin-release.yml@v1`
  — this repo carries neither script, just the calling job; the
  tag and the Release are checked and created independently, so a
  failure between the two never leaves a tag with no Release).

**Branch-protection ruleset requires `Shared / Pre-Merge Checks`**, the
reusable PR job that `ci.yml` calls from dotty (`estate-pr-ci.yml`); the
ruleset does not set `strict`. The plugin validation, hook tests, shared-copy
and standalone checks run in the author's pre-push hooks
(`.github/scripts/check-push.sh`), and `drift-check` runs daily in
`drift-check.yml`; none of them is a PR job.

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
