#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2088  # payload strings are LITERAL shell text ($GH, ~/…): never expanded here
# Test suite for the fail-closed PR-body TEMPLATE guard:
#   ../hooks/gh-pr-body-template-guard.sh   (PreToolUse guard for gh pr create/edit)
#
# Self-contained: builds throwaway git repos carrying the REAL estate template
# (tests/fixtures/pull_request_template.md, a verbatim copy of dotty's
# .github/pull_request_template.md — the file the vendored checker is written
# against) and drives the hook with PreToolUse JSON on stdin. It never runs
# `gh`. python3 and jq are hard requirements of the hook and of this suite.
#
# Bodies carry a SENTINEL word so the "never echoed" cases can prove the body
# text does not reach stderr; only the checker's own diagnostic lines (which
# quote headings and template placeholders) may.
#
# Run: bash this-file.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"

HOOK="${HOOK:-${SCRIPT_DIR}/../hooks/gh-pr-body-template-guard.sh}"
CHECKER="${SCRIPT_DIR}/../hooks/pr-body-check.py"
COMMON="${SCRIPT_DIR}/../hooks/gitleaks-common.sh"
FIXTURE_TPL="${SCRIPT_DIR}/fixtures/pull_request_template.md"
for f in "$HOOK" "$CHECKER" "$COMMON" "$FIXTURE_TPL"; do
	[[ -f "$f" ]] || {
		echo "FATAL: missing $f"
		exit 2
	}
done
command -v jq >/dev/null 2>&1 || {
	echo "FATAL: jq not on PATH — suite cannot run."
	exit 2
}
command -v python3 >/dev/null 2>&1 || {
	echo "FATAL: python3 not on PATH — suite cannot run."
	exit 2
}

# --- Fixture -------------------------------------------------------------------
TMP="$(mktemp -d -t gh-pr-tpl-guard-test.XXXXXX)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

init_repo() { # <path>
	GIT_CONFIG_GLOBAL=/dev/null git init -q "$1"
}
# An enrolled repo: carries the real template.
REPO="$TMP/repo"
init_repo "$REPO"
mkdir -p "$REPO/.github" "$REPO/sub"
cp "$FIXTURE_TPL" "$REPO/.github/pull_request_template.md"
# A repo with NO template (not enrolled) and a plain directory (not a repo).
NOTPL="$TMP/notpl"
init_repo "$NOTPL"
NOREPO="$TMP/norepo"
mkdir -p "$NOREPO"

SENTINEL="zqx-sentinel-$RANDOM"

GOOD_BODY="<!-- pr-body:v1 -->
## Intent
Make the guard fire locally. ${SENTINEL}

## What changed
One hook.

## Verification
Suite green.

## Risk and blast radius
Low.

## Rollback
Revert the commit.

## Ticket
None — housekeeping.

## Dependencies
None"

# Missing marker: the first line is a heading.
NO_MARKER_BODY="${GOOD_BODY#<!-- pr-body:v1 -->$'\n'}"
# A leftover placeholder: the Intent section still carries the template's line.
PLACEHOLDER_BODY="${GOOD_BODY/Make the guard fire locally. ${SENTINEL}/The problem and the intended outcome.}"
# A missing required heading: Rollback removed. (The pattern is quoted: an
# unquoted leading `#` in ${var/pat/} is bash's start-of-string anchor.)
NO_HEADING_BODY="${GOOD_BODY/"## Rollback"$'\n'"Revert the commit."$'\n'$'\n'/}"
[[ "$NO_HEADING_BODY" != *"## Rollback"* ]] || {
	echo "FATAL: fixture NO_HEADING_BODY still carries ## Rollback"
	exit 2
}

printf '%s\n' "$GOOD_BODY" >"$TMP/good.md"
printf '%s\n' "$NO_MARKER_BODY" >"$TMP/nomarker.md"
printf '%s\n' "$GOOD_BODY" >"$REPO/body.md"
printf '%s\n' "$GOOD_BODY" >"$REPO/sub/body.md"
printf '%s\n' "$NO_HEADING_BODY" >"$REPO/sub/bad.md"

# --- Runners -------------------------------------------------------------------
ERRFILE="$TMP/stderr.txt"
mkjson() { # <command> <cwd>
	jq -n --arg cmd "$1" --arg cwd "$2" '{tool_name:"Bash", tool_input:{command:$cmd}, cwd:$cwd}'
}
run_hook() { # <json> [pathspec]
	printf '%s' "$1" | env PATH="${2:-$PATH}" bash "$HOOK" >/dev/null 2>"$ERRFILE"
	RC=$?
}
# PATH bin dir with every tool the hook uses EXCEPT one (missing-dependency cases).
HOOK_TOOLS=(bash dirname jq git python3 mktemp cat tr rm)
make_bin() { # <exclude-tool> -> prints bindir
	local d t p
	d="$(mktemp -d)"
	for t in "${HOOK_TOOLS[@]}"; do
		[[ "$t" == "$1" ]] && continue
		p="$(command -v "$t" 2>/dev/null)" && ln -s "$p" "$d/$t" 2>/dev/null
	done
	printf '%s' "$d"
}
body_not_echoed() { # <label>
	if grep -qF "$SENTINEL" "$ERRFILE"; then
		fail "$1: body never echoed to stderr" "the sentinel body text appeared in the block message"
	else
		pass "$1: body never echoed to stderr"
	fi
}
cmd_body() { # <gh-prefix> <verb> <body> -> a command string with the body double-quoted
	printf '%s pr %s --title "t" --body "%s"' "$1" "$2" "$3"
}

# ============================================================================
# Conforming bodies pass, in every shape.
# ============================================================================
section "conforming inline --body passes (bare gh)"
run_hook "$(mkjson "$(cmd_body gh create "$GOOD_BODY")" "$REPO")"
assert_eq "bare gh, good inline body exits 0 (allow)" "0" "$RC"

section "conforming inline --body passes via the wrapper path and \$GH"
run_hook "$(mkjson "$(cmd_body /opt/estate/bin/gh create "$GOOD_BODY")" "$REPO")"
assert_eq "wrapper path, good body exits 0" "0" "$RC"
run_hook "$(mkjson "$(cmd_body '$GH' create "$GOOD_BODY")" "$REPO")"
assert_eq "\$GH, good body exits 0" "0" "$RC"
run_hook "$(mkjson "$(cmd_body '"${GH}"' create "$GOOD_BODY")" "$REPO")"
assert_eq "\"\${GH}\", good body exits 0" "0" "$RC"

section "conforming --body-file passes (absolute; relative; -F; --body-file=)"
run_hook "$(mkjson "gh pr create --title t --body-file $TMP/good.md" "$REPO")"
assert_eq "absolute --body-file exits 0" "0" "$RC"
run_hook "$(mkjson 'gh pr create --title t --body-file body.md' "$REPO")"
assert_eq "relative --body-file resolves against cwd, exits 0" "0" "$RC"
run_hook "$(mkjson "/opt/estate/bin/gh pr create --title t -F $TMP/good.md" "$REPO")"
assert_eq "-F via wrapper path exits 0" "0" "$RC"
run_hook "$(mkjson "\$GH pr create --title t --body-file=$TMP/good.md" "$REPO")"
assert_eq "--body-file= via \$GH exits 0" "0" "$RC"

section "cd prefix: the template AND a relative --body-file resolve where gh runs"
run_hook "$(mkjson "cd $REPO && gh pr create --title t --body-file body.md" "$NOREPO")"
assert_eq "cd <repo> && … from a non-repo cwd exits 0" "0" "$RC"
run_hook "$(mkjson "cd $REPO && cd sub && \$GH pr create --title t -F body.md" "$NOREPO")"
assert_eq "chained cd, relative -F in the effective dir exits 0" "0" "$RC"
run_hook "$(mkjson "cd $REPO && cd sub && gh pr create --title t -F bad.md" "$NOREPO")"
assert_eq "chained cd, BAD body in the effective dir exits 2 (block)" "2" "$RC"
grep -q "missing required section heading" "$ERRFILE" && pass "names the missing heading" || fail "names the missing heading" "$(cat "$ERRFILE")"

section "heredoc'd script running \$GH pr create with a good body passes"
run_hook "$(mkjson "$(printf 'bash <<'"'"'B'"'"'\nGH=/opt/estate/bin/gh\n$GH pr create --title t --body-file %s\nB' "$TMP/good.md")" "$REPO")"
assert_eq "heredoc \$GH good body-file exits 0" "0" "$RC"

section "--body= and -b<text> short forms are read"
run_hook "$(mkjson "gh pr create --title t --body=\"$GOOD_BODY\"" "$REPO")"
assert_eq "--body= good exits 0" "0" "$RC"
run_hook "$(mkjson "gh pr create --title t -b\"$NO_MARKER_BODY\"" "$REPO")"
assert_eq "-b<text> bad body exits 2 (block)" "2" "$RC"

# ============================================================================
# Non-conforming bodies BLOCK, quoting the checker's line, never the body.
# ============================================================================
section "missing marker -> BLOCK with the checker's line"
run_hook "$(mkjson "$(cmd_body gh create "$NO_MARKER_BODY")" "$REPO")"
assert_eq "missing marker exits 2 (block)" "2" "$RC"
grep -q "missing the \`<!-- pr-body:v1 -->\` marker as the first line" "$ERRFILE" && pass "quotes the checker's marker line" || fail "quotes the checker's marker line" "$(cat "$ERRFILE")"
grep -q "This is the same check CI runs; fix the body before \`gh pr create\`" "$ERRFILE" && pass "ends with the CI-parity line" || fail "ends with the CI-parity line" "$(cat "$ERRFILE")"
grep -q "PR-template-guard BLOCKED" "$ERRFILE" && pass "block title in gl_block format" || fail "block title in gl_block format" "$(cat "$ERRFILE")"
body_not_echoed "missing marker"

section "missing marker via --body-file -> BLOCK"
run_hook "$(mkjson "gh pr create --title t --body-file $TMP/nomarker.md" "$REPO")"
assert_eq "body-file missing marker exits 2 (block)" "2" "$RC"
grep -q "missing the" "$ERRFILE" && pass "names the missing marker" || fail "names the missing marker" "$(cat "$ERRFILE")"

section "leftover template placeholder -> BLOCK"
run_hook "$(mkjson "$(cmd_body gh create "$PLACEHOLDER_BODY")" "$REPO")"
assert_eq "placeholder exits 2 (block)" "2" "$RC"
grep -q "untouched template placeholder" "$ERRFILE" && pass "names the untouched placeholder" || fail "names the untouched placeholder" "$(cat "$ERRFILE")"
grep -q "The problem and the intended outcome." "$ERRFILE" && pass "quotes the template's placeholder text (not body content)" || fail "quotes the template's placeholder text" "$(cat "$ERRFILE")"

section "missing required heading -> BLOCK"
run_hook "$(mkjson "$(cmd_body gh create "$NO_HEADING_BODY")" "$REPO")"
assert_eq "missing heading exits 2 (block)" "2" "$RC"
grep -q "missing required section heading: \`## Rollback\`" "$ERRFILE" && pass "names the missing heading" || fail "names the missing heading" "$(cat "$ERRFILE")"
body_not_echoed "missing heading"

section "wrapper path and \$GH with a bad body BLOCK too (scope, not verdict, widened)"
run_hook "$(mkjson "$(cmd_body /opt/estate/bin/gh create "$NO_MARKER_BODY")" "$REPO")"
assert_eq "wrapper path bad body exits 2" "2" "$RC"
run_hook "$(mkjson "$(cmd_body '$GH' create "$NO_MARKER_BODY")" "$REPO")"
assert_eq "\$GH bad body exits 2" "2" "$RC"

section "empty body -> BLOCK"
run_hook "$(mkjson 'gh pr create --title t --body ""' "$REPO")"
assert_eq "empty --body exits 2 (block)" "2" "$RC"
grep -q "PR body is empty" "$ERRFILE" && pass "checker names the empty body" || fail "checker names the empty body" "$(cat "$ERRFILE")"

# ============================================================================
# create with no body flag BLOCKS; edit with no body flag passes.
# ============================================================================
section "'gh pr create' with no body flag (--fill / -f / --web / bare) -> BLOCK"
for c in 'gh pr create --fill' 'gh pr create -f' 'gh pr create --fill-first' 'gh pr create --web' 'gh pr create --title "t"' '/opt/estate/bin/gh pr create --fill' '$GH pr create --fill'; do
	run_hook "$(mkjson "$c" "$REPO")"
	assert_eq "'$c' exits 2 (block)" "2" "$RC"
done
grep -q "no PR body" "$ERRFILE" && pass "names the missing body" || fail "names the missing body" "$(cat "$ERRFILE")"
grep -q "\-\-body-file <path>" "$ERRFILE" && pass "gives the remediation" || fail "gives the remediation" "$(cat "$ERRFILE")"
grep -q "This is the same check CI runs" "$ERRFILE" && pass "ends with the CI-parity line" || fail "ends with the CI-parity line" "$(cat "$ERRFILE")"

section "'gh pr edit' without a body flag -> PASS (nothing to check)"
for c in 'gh pr edit 12 --title "t"' 'gh pr edit 12 --add-label x' '/opt/estate/bin/gh pr edit 12 --add-reviewer a' '$GH pr edit --title t'; do
	run_hook "$(mkjson "$c" "$REPO")"
	assert_eq "'$c' exits 0 (allow)" "0" "$RC"
done

section "'gh pr edit' WITH a bad body -> BLOCK; with a good body -> PASS"
run_hook "$(mkjson "$(cmd_body gh 'edit 12' "$NO_MARKER_BODY")" "$REPO")"
assert_eq "edit bad body exits 2 (block)" "2" "$RC"
run_hook "$(mkjson "$(cmd_body gh 'edit 12' "$GOOD_BODY")" "$REPO")"
assert_eq "edit good body exits 0" "0" "$RC"

# ============================================================================
# No template -> pass silently (not enrolled).
# ============================================================================
section "repo without a template -> PASS even with a bad body / no body"
run_hook "$(mkjson "$(cmd_body gh create "$NO_MARKER_BODY")" "$NOTPL")"
assert_eq "no template, bad body exits 0 (not enrolled)" "0" "$RC"
[[ -s "$ERRFILE" ]] && fail "no template: silent" "$(cat "$ERRFILE")" || pass "no template: silent"
run_hook "$(mkjson 'gh pr create --fill' "$NOTPL")"
assert_eq "no template, --fill exits 0" "0" "$RC"
run_hook "$(mkjson 'gh pr create --fill' "$NOREPO")"
assert_eq "not a repo at all, --fill exits 0" "0" "$RC"
run_hook "$(mkjson "cd $NOTPL && gh pr create --fill" "$REPO")"
assert_eq "cd into a non-enrolled repo from an enrolled cwd: the cd target wins, exits 0" "0" "$RC"

# ============================================================================
# Fail-closed: unreadable paths, indeterminate bodies, parse failures, deps.
# ============================================================================
section "-F / --body-file path unresolvable -> BLOCK"
run_hook "$(mkjson "gh pr create --title t -F $TMP/nope-does-not-exist.md" "$REPO")"
assert_eq "-F missing exits 2 (block)" "2" "$RC"
grep -qi "unreadable" "$ERRFILE" && pass "names the unreadable path" || fail "names the unreadable path" "$(cat "$ERRFILE")"
run_hook "$(mkjson 'gh pr create --title t --body-file nope.md' "$REPO")"
assert_eq "relative --body-file missing exits 2 (block)" "2" "$RC"

section "-F as the final token with no argument -> BLOCK"
run_hook "$(mkjson 'gh pr create --title t -F' "$REPO")"
assert_eq "-F no-arg exits 2 (block)" "2" "$RC"
grep -q "no argument" "$ERRFILE" && pass "names the missing argument" || fail "names the missing argument" "$(cat "$ERRFILE")"

section "shell-aware tokenizer: '-F' inside a quoted body is NOT the flag"
BODY_WITH_F="${GOOD_BODY/One hook./Use -F to pass a file. Also --body-file works.}"
run_hook "$(mkjson "$(cmd_body gh create "$BODY_WITH_F")" "$REPO")"
assert_eq "good body mentioning -F exits 0 (no spurious block)" "0" "$RC"

section "body computed at run time (\$(cat <<EOF), \$VAR, --body-file -) -> BLOCK, fail-closed"
run_hook "$(mkjson 'gh pr create --title t --body "$(cat <<'"'"'EOF'"'"'
<!-- pr-body:v1 -->
## Intent
x
EOF
)"' "$REPO")"
assert_eq "\$(cat <<EOF) body exits 2 (block)" "2" "$RC"
grep -q "computed at run time" "$ERRFILE" && pass "names the indeterminate body" || fail "names the indeterminate body" "$(cat "$ERRFILE")"
grep -q "\-\-body-file <path>" "$ERRFILE" && pass "gives the body-file remediation" || fail "gives the body-file remediation" "$(cat "$ERRFILE")"
run_hook "$(mkjson 'gh pr create --title t --body "$BODY"' "$REPO")"
assert_eq "--body \"\$BODY\" exits 2 (block)" "2" "$RC"
run_hook "$(mkjson 'gh pr create --title t --body-file -' "$REPO")"
assert_eq "--body-file - (stdin) exits 2 (block)" "2" "$RC"

section "unbalanced quotes -> BLOCK (cannot tokenize)"
run_hook "$(mkjson 'gh pr create --title t --body "unterminated' "$REPO")"
assert_eq "unterminated quote exits 2 (block)" "2" "$RC"
grep -q "could not be parsed" "$ERRFILE" && pass "names the parse failure" || fail "names the parse failure" "$(cat "$ERRFILE")"

section "missing python3 -> BLOCK (names install)"
BIN_NO_PY="$(make_bin python3)"
run_hook "$(mkjson "$(cmd_body gh create "$GOOD_BODY")" "$REPO")" "$BIN_NO_PY"
assert_eq "missing python3 exits 2 (block)" "2" "$RC"
grep -q "python3 is not installed" "$ERRFILE" && pass "names the missing python3" || fail "names the missing python3" "$(cat "$ERRFILE")"

section "missing jq -> BLOCK (names install)"
BIN_NO_JQ="$(make_bin jq)"
run_hook "$(mkjson "$(cmd_body gh create "$GOOD_BODY")" "$REPO")" "$BIN_NO_JQ"
assert_eq "missing jq exits 2 (block)" "2" "$RC"
grep -q "jq is not installed" "$ERRFILE" && pass "names the missing jq" || fail "names the missing jq" "$(cat "$ERRFILE")"

section "missing vendored checker -> BLOCK"
ISO="$TMP/iso"
mkdir -p "$ISO"
cp "$HOOK" "$COMMON" "$ISO/"
printf '%s' "$(mkjson "$(cmd_body gh create "$GOOD_BODY")" "$REPO")" | bash "$ISO/gh-pr-body-template-guard.sh" >/dev/null 2>"$ERRFILE"
RC=$?
assert_eq "checker absent exits 2 (block)" "2" "$RC"
grep -q "vendored checker is missing" "$ERRFILE" && pass "names the missing checker" || fail "names the missing checker" "$(cat "$ERRFILE")"

section "vendored checker is byte-identical to the fixture-adjacent SOURCE claim (self-consistency)"
[[ -f "${SCRIPT_DIR}/../hooks/pr-body-check.SOURCE" ]] && pass "pr-body-check.SOURCE exists" || fail "pr-body-check.SOURCE exists" "missing"
grep -q "lexijamesesq/dotty:.github/scripts/pr-body-check.py @ [0-9a-f]\{40\}" "${SCRIPT_DIR}/../hooks/pr-body-check.SOURCE" && pass "SOURCE names the dotty path and a commit sha" || fail "SOURCE names the dotty path and a commit sha" "$(cat "${SCRIPT_DIR}/../hooks/pr-body-check.SOURCE")"

# ============================================================================
# Out of scope.
# ============================================================================
section "out of scope: non-PR commands, mere mentions, non-Bash tools -> silent exit 0"
for c in 'git status' 'gh pr view 12' 'echo "gh pr create --fill"' '/opt/bin/ghost pr create --fill' 'gh pr list'; do
	run_hook "$(mkjson "$c" "$REPO")"
	assert_eq "'$c' exits 0" "0" "$RC"
	[[ -s "$ERRFILE" ]] && fail "'$c' is silent" "$(cat "$ERRFILE")" || pass "'$c' is silent"
done
run_hook "$(jq -n --arg cwd "$REPO" '{tool_name:"Read", tool_input:{file_path:"/x"}, cwd:$cwd}')"
assert_eq "non-Bash tool exits 0" "0" "$RC"

finish
