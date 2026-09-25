#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2088  # payload strings are LITERAL shell text ($GH, ~/…): never expanded here
# Test suite for estate-hooks/hooks/pr-cache.sh — the SCOPE decision only.
#
# pr-cache.sh refreshes the statusline's PR cache. As a PostToolUse hook it
# must fire on a `gh pr create` / `gh pr merge` in every shape the estate uses
# (bare gh, the wrapper by path, a variable holding it, a heredoc'd script)
# and stay out of every other Bash command — each refresh costs one network
# round-trip per declared repo. The bare-`gh`-only regex it used to carry was
# silent on every wrapper-path shape (the same receipted defect as
# pr-verdict-watch-arm.sh).
#
# Observable: the hook creates its cache directory under $TMPDIR only AFTER
# the scope gate passes (and CLAUDE.md exists). A fresh TMPDIR per case makes
# "did the directory appear" the scope verdict, independent of `yq` (which the
# hook needs before it ever reaches `gh`) being installed. `gh` is stubbed on
# PATH regardless, recording every call; when `yq` is present the stub's
# record is asserted too. No network: every case is a synthetic payload.
#
# Run: bash this-file.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"

HOOK="${HOOK:-${SCRIPT_DIR}/../hooks/pr-cache.sh}"
[[ -f "$HOOK" ]] || {
	echo "FATAL: $HOOK not found"
	exit 2
}
command -v jq >/dev/null 2>&1 || {
	echo "FATAL: jq required for these tests"
	exit 2
}

TMP="$(mktemp -d -t pr-cache-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT INT TERM

# A project dir with a CLAUDE.md declaring one build_home repo (a real, empty
# git repo), so the hook has somewhere to go once scope passes.
PROJECT="$TMP/project"
REPO="$TMP/repo"
mkdir -p "$PROJECT"
GIT_CONFIG_GLOBAL=/dev/null git init -q "$REPO"
printf -- '---\nbuild_home:\n  - %s\n---\n# fixture\n' "$REPO" >"$PROJECT/CLAUDE.md"

# gh stub: records argv, answers `pr list` with an empty array.
STUB="$TMP/bin"
mkdir -p "$STUB"
cat >"$STUB/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_CALLS"
[[ "$1" == "pr" && "$2" == "list" ]] && printf '[]'
exit 0
GH
chmod +x "$STUB/gh"
# The hook wraps each gh call in `timeout`, which is not on a stock macOS
# PATH (it is coreutils). A passthrough stub keeps the gh assertion about
# SCOPE on every platform, not about whether coreutils is installed.
printf '#!/usr/bin/env bash\nshift\nexec "$@"\n' >"$STUB/timeout"
chmod +x "$STUB/timeout"
HAVE_YQ=0
command -v yq >/dev/null 2>&1 && HAVE_YQ=1

# run_case <command> -> sets RC, CACHE_MADE (0/1), GH_CALLED (0/1)
run_case() {
	local tmpdir="$TMP/case-$RANDOM$RANDOM" calls
	mkdir -p "$tmpdir"
	calls="$tmpdir/gh-calls"
	: >"$calls"
	RC=0
	jq -nc --arg cmd "$1" --arg cwd "$PROJECT" \
		'{tool_name:"Bash",tool_input:{command:$cmd},tool_response:"ok\n",cwd:$cwd}' |
		env -u CLAUDE_PROJECT_DIR TMPDIR="$tmpdir" GH_CALLS="$calls" PATH="$STUB:$PATH" \
			bash "$HOOK" >/dev/null 2>&1 || RC=$?
	if [[ -d "$tmpdir/claude-statusline-pr" ]]; then CACHE_MADE=1; else CACHE_MADE=0; fi
	if [[ -s "$calls" ]]; then GH_CALLED=1; else GH_CALLED=0; fi
}

fires() { # <label> <command>
	run_case "$2"
	assert_eq "$1: exits 0" "0" "$RC"
	assert_eq "$1: in scope (cache dir created)" "1" "$CACHE_MADE"
	if [[ "$HAVE_YQ" -eq 1 ]]; then
		assert_eq "$1: refreshed via gh (stub called)" "1" "$GH_CALLED"
	fi
}
silent() { # <label> <command>
	run_case "$2"
	assert_eq "$1: exits 0" "0" "$RC"
	assert_eq "$1: out of scope (no cache dir)" "0" "$CACHE_MADE"
	assert_eq "$1: gh never called" "0" "$GH_CALLED"
}

section "In scope: create/merge in every shape the estate uses"
fires "bare gh pr create" 'gh pr create --title x --body y'
fires "bare gh pr merge" 'gh pr merge 12 --squash'
fires "wrapper path /opt/estate/bin/gh pr create" '/opt/estate/bin/gh pr create --fill'
fires "wrapper path ~/.local/bin/gh pr merge" '~/.local/bin/gh pr merge 3 --squash --delete-branch'
fires "variable \$GH pr create" '$GH pr create --fill'
fires "braced variable \${GH} pr merge" '${GH} pr merge 3'
fires "quoted \"\$GH\" pr create" '"$GH" pr create --fill'
fires "env assignment + wrapper path" 'GH_TOKEN=x /opt/estate/bin/gh pr merge 3'
fires "heredoc'd script running \$GH pr create" $'bash <<\'B\'\nGH=/opt/estate/bin/gh\n$GH pr create --fill\nB'
fires "after a cd prefix" 'cd ~/Repos/x && /opt/estate/bin/gh pr create --fill'
fires "line continuation across the subcommand" $'gh pr \\\ncreate --fill'

section "Out of scope: everything else stays silent (no network)"
silent "gh pr view" 'gh pr view 12'
silent "wrapper-path gh pr view" '/opt/estate/bin/gh pr view 12'
silent "gh pr list" 'gh pr list --state open'
silent "mere mention in an echo" 'echo "gh pr create later"'
silent "mere mention of \$GH pr create in an echo" 'echo "$GH pr create"'
silent "a path merely containing gh" '/opt/bin/ghost pr create'
silent "look-alike subcommand" 'gh pr createfoo'
silent "unrelated command" 'git status'

section "Fail-open on odd input"
run_case ''
assert_eq "empty command: exits 0" "0" "$RC"
assert_eq "empty command: no cache dir" "0" "$CACHE_MADE"

finish
