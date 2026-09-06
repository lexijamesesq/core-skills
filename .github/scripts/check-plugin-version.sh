#!/usr/bin/env bash
# check-plugin-version.sh <plugin_dir> <plugin_name>
#
# PR-time check (no writes). Compares the plugin's tree against
# its highest existing tag, not the tag matching the declared version, so
# the check stays live even if the push-time tagger is behind (a merged-but-
# untagged version still trips a later mismatch instead of a free pass).
#
# No existing tag => nothing to compare yet => pass (day-one / new plugin).
# Tree identical to the tag => pass.
# Tree changed and the declared version isn't above the tag's => fail loud.
set -euo pipefail

PLUGIN_DIR="$1"
PLUGIN_NAME="$2"

LATEST_TAG="$(git tag -l "${PLUGIN_NAME}--v*" --sort=-v:refname | head -1)"

if [[ -z "$LATEST_TAG" ]]; then
  echo "PASS $PLUGIN_NAME: no existing tag, nothing to compare yet"
  exit 0
fi

TAG_VERSION="${LATEST_TAG#"${PLUGIN_NAME}--v"}"
# plugin.json's content comes from the PR branch — pass PLUGIN_DIR (a
# workflow-controlled literal) as an argv, and read the version through
# json, never string-interpolated into a -c source. The version string
# itself is untrusted PR content; it's compared below via os.environ, not
# interpolated into any script text.
CURRENT_VERSION="$(python3 -c "
import json, sys
print(json.load(open(sys.argv[1] + '/.claude-plugin/plugin.json'))['version'])
" "$PLUGIN_DIR")"

# .pre-commit-config.yaml and .github/CODEOWNERS are repo-level
# infrastructure (a dotty pin bump, a path-ownership rule), never plugin
# content -- excluded from the diff regardless of PLUGIN_DIR. For a
# single-plugin repo (PLUGIN_DIR=".", the whole repo is the plugin) these
# files sit inside PLUGIN_DIR and, unexcluded, made every dotty-bump PR
# fail this check for a change that isn't plugin content at all (found
# live: wiki and publish-skills both needed a hand version bump on every
# dotty-bump PR for this exact reason; the same class of failure recurred
# for CODEOWNERS on every single-plugin repo). A no-op exclude for a
# multi-plugin repo (PLUGIN_DIR a subdirectory) where these files were
# never inside PLUGIN_DIR to begin with.
if git diff --quiet "$LATEST_TAG" HEAD -- "$PLUGIN_DIR" \
    ":(exclude)${PLUGIN_DIR%/}/.pre-commit-config.yaml" \
    ":(exclude)${PLUGIN_DIR%/}/.github/CODEOWNERS"; then
  echo "PASS $PLUGIN_NAME: tree identical to $LATEST_TAG"
  exit 0
fi

VERSION_BUMPED="$(CURRENT_VERSION="$CURRENT_VERSION" TAG_VERSION="$TAG_VERSION" python3 -c "
import os

def parse(v):
    return tuple(int(x) for x in v.split('.'))

current = parse(os.environ['CURRENT_VERSION'])
tag = parse(os.environ['TAG_VERSION'])
print('1' if current > tag else '0')
")"

if [[ "$VERSION_BUMPED" == "1" ]]; then
  echo "PASS $PLUGIN_NAME: tree changed, version bumped $TAG_VERSION -> $CURRENT_VERSION"
  exit 0
fi

echo "FAIL $PLUGIN_NAME: plugin content changed without a version bump (still $CURRENT_VERSION, last tag $LATEST_TAG)"
exit 1
