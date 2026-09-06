#!/usr/bin/env bash
# tag-plugin-release.sh <plugin_dir> <plugin_name>
#
# Push-time (main only). If the plugin's declared version isn't
# tagged on origin yet, cuts the tag and a GitHub Release. Idempotent and
# re-entrant: the tag-exists check is remote-authoritative
# (git ls-remote), and the Release is checked and created independently of
# the tag so a failure between the two steps doesn't leave a tag with no
# Release forever.
#
# LEX-757: tag CREATION is restricted by ruleset to this repo's own
# deploy key (any session/GITHUB_TOKEN push is refused) — the tag is
# created locally, then pushed over SSH with that key
# ($RELEASE_DEPLOY_KEY_PATH, set by the workflow from the `release`
# environment's secret, never a repository secret). Release creation
# stays on GITHUB_TOKEN via `gh`: attaching a Release to an existing tag
# needs no tag-creation permission.
set -euo pipefail

PLUGIN_DIR="$1"
PLUGIN_NAME="$2"

# PLUGIN_DIR is a workflow-controlled literal (never interpolated into
# untrusted content); the version string plugin.json holds is read via
# argv/json, never through a python -c string interpolation, since this
# job holds contents: write + a real GH token.
CURRENT_VERSION="$(python3 -c "
import json, sys
print(json.load(open(sys.argv[1] + '/.claude-plugin/plugin.json'))['version'])
" "$PLUGIN_DIR")"
TAG="${PLUGIN_NAME}--v${CURRENT_VERSION}"

if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  # Reuse and verify, never move: the tag already exists (a prior run's
  # push succeeded before this run, or before a Release-creation retry).
  # fetch-tags:true in this job's checkout means it's already local —
  # peel it to its commit and confirm that commit precedes HEAD before
  # trusting it as this version's tag. A tag whose commit is NOT an
  # ancestor of HEAD is a genuine anomaly (a version string reused across
  # unrelated history) and must never be silently accepted or force-moved.
  TAG_COMMIT="$(git rev-parse "refs/tags/$TAG^{commit}")"
  if ! git merge-base --is-ancestor "$TAG_COMMIT" HEAD; then
    echo "$PLUGIN_NAME: FATAL — $TAG already exists at $TAG_COMMIT, which is not an ancestor of this run's HEAD. Refusing to treat it as this version's tag (never moving an existing tag)." >&2
    exit 1
  fi
  echo "$PLUGIN_NAME: $TAG already exists on origin at $TAG_COMMIT (verified ancestor of HEAD) — reusing, not re-tagging"
else
  echo "$PLUGIN_NAME: tagging $TAG"
  claude plugin tag -m "%s" "$PLUGIN_DIR"
  GIT_SSH_COMMAND="ssh -i $RELEASE_DEPLOY_KEY_PATH -o IdentitiesOnly=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=accept-new" \
    git push "git@github.com:$(gh repo view --json nameWithOwner -q .nameWithOwner).git" "refs/tags/$TAG"
fi

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "$PLUGIN_NAME: Release $TAG already exists"
  exit 0
fi

PREV_TAG="$(git tag -l "${PLUGIN_NAME}--v*" --sort=-v:refname | grep -vF "$TAG" | head -1 || true)"

echo "$PLUGIN_NAME: cutting Release $TAG"
if [[ -n "$PREV_TAG" ]]; then
  gh release create "$TAG" --generate-notes --notes-start-tag "$PREV_TAG"
else
  gh release create "$TAG" --generate-notes
fi
