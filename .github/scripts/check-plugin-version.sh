#!/usr/bin/env bash
# check-plugin-version.sh <plugin_dir> <plugin_name>
#
# PR-time check (no writes) — LEX-701. Compares the plugin's tree against
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
CURRENT_VERSION="$(python3 -c "import json; print(json.load(open('$PLUGIN_DIR/.claude-plugin/plugin.json'))['version'])")"

if git diff --quiet "$LATEST_TAG" HEAD -- "$PLUGIN_DIR"; then
  echo "PASS $PLUGIN_NAME: tree identical to $LATEST_TAG"
  exit 0
fi

VERSION_BUMPED="$(python3 -c "
def parse(v):
    return tuple(int(x) for x in v.split('.'))
print('1' if parse('$CURRENT_VERSION') > parse('$TAG_VERSION') else '0')
")"

if [[ "$VERSION_BUMPED" == "1" ]]; then
  echo "PASS $PLUGIN_NAME: tree changed, version bumped $TAG_VERSION -> $CURRENT_VERSION"
  exit 0
fi

echo "FAIL $PLUGIN_NAME: plugin content changed without a version bump (still $CURRENT_VERSION, last tag $LATEST_TAG)"
exit 1
