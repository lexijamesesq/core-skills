#!/usr/bin/env bash
# gh-pr-body-template-guard.sh — FAIL-CLOSED PreToolUse guard that runs the
# estate's PR-body TEMPLATE check on a `gh pr create` / `gh pr edit` body
# BEFORE the command runs — the same structural check CI's required
# pr-body-check gate runs on the PR once it exists.
#
# WHY LOCAL: the template check was the single biggest cause of PR-check
# failure in the estate, and it failed on GitHub, after the PR was open,
# where the session that opened the PR never looks (it creates and hopes).
# Moving the check in front of `gh pr create` turns a red check nobody reads
# into a block the session must fix before the PR exists. The verdict is
# the checker's own: hooks/pr-body-check.py is a BYTE-IDENTICAL copy of
# dotty's .github/scripts/pr-body-check.py, copied from lexijamesesq/dotty
# main at commit bfc658d6064e9a52be563b85c172e7faa1a15cad (2026-09-25); a drift
# audit compares bytes — never edit it here, re-copy it from dotty. What
# passes here passes CI, and what CI rejects is rejected here, by the same
# code.
#
# THE TEMPLATE is the repository's own .github/pull_request_template.md —
# the one the provisioner installs in every enrolled repo — located from the
# directory gh will actually run in: the target of a leading `cd <path> &&`
# chain when the command has one (the PreToolUse payload reports the SESSION
# cwd, which is often the vault), else the payload cwd (gh_scope_target_dir,
# gh-scope-common.sh). The guard switches on ONLY for the ESTATE's template:
# its first line must be exactly `<!-- pr-body:v1 -->`, the marker the
# checker derives every rule from. No template there, or a template without
# that first line (an outside project with its own PR template) -> exit 0
# silently: not the estate's lane, and CI will not run this check on it
# either. Gating on mere existence blocked PRs in outside projects with
# their own templates by demanding the estate's format (non-author review,
# PR #111). (gh-pr-body-guard.sh's ruleset paths 3 and 4 — the fixed-path
# and env-var rulesets — are gitleaks-specific and have no analogue here; a
# template is a per-repo file.)
#
# THE BODY, extracted with the SAME shell-aware tokenizer the secret guard
# uses (python3 shlex.split), never whitespace splitting — a `-F` mentioned
# inside a quoted body stays inside the body token and is not the flag:
#   --body <text> / -b <text> / --body=<text> / -b<text>    inline text
#   --body-file <path> / -F <path> / --body-file= / -F<path>  the file's
#     contents, a relative path resolved against the directory gh runs in
#     (the cd-chain target, else the payload cwd), exactly as the secret
#     guard resolves it
#   create with NO body flag (including --fill, --fill-first, -f, --web)
#     -> BLOCK: the template requires the marker as the FIRST line and gh's
#     own fill never produces it, so CI would reject the PR anyway.
#   edit with no body flag -> exit 0: nothing to check.
#
# FAIL-CLOSED contract (the secret guard's, verbatim): an inability to run
# the check BLOCKS, never silently passes.
#   * jq / python3 missing                      -> BLOCK
#     (jq is needed before the guard can even self-scope, and the hook is
#     registered with no `if:` prefilter, so a machine WITHOUT jq is blocked
#     on EVERY Bash call — fail-closed by contract; provisioned machines
#     carry jq. The former prefilter only ever narrowed this to commands
#     carrying $VAR or $(...), and dropped the estate's real creates.)
#   * the vendored checker missing              -> BLOCK
#   * the command cannot be tokenized           -> BLOCK
#   * --body / --body-file with no argument     -> BLOCK
#   * --body-file / -F unreadable, or `-` (stdin) -> BLOCK
#   * a body that is computed at run time — a `$(...)`, a backtick, or a
#     `$VAR` inside the body token, or a heredoc with an UNQUOTED delimiter
#     (`<<EOF`, which the shell expands) — cannot be read here -> BLOCK,
#     with the fix: write the body to a file and pass --body-file
#   The one statically-safe computed shape is READ, not blocked:
#     --body "$(cat <<'EOF' ... EOF)"  (delimiter quoted, 'EOF' or "EOF")
#   is the harness's own default for a PR body and expands nothing, so its
#   literal text is extracted from the raw command and checked as-is.
#   * checker exit 1 (findings)                 -> BLOCK, quoting its lines
#   * checker exit 2, a kill signal, a crash, no output at all: ANY code
#     other than 0 or 1                         -> BLOCK, "did not complete"
#   * checker exit 0                            -> exit 0 (with or without
#     output: silence is the checker's success shape)
#   * the guard itself aborting for any reason after the command is known
#     to publish a PR                            -> BLOCK (EXIT trap; see it)
# The body is never echoed: the block quotes only the checker's own
# diagnostic lines, which name headings and template placeholders, never
# body content. The body reaches the checker through a JSON event file
# written with `jq -n --arg` (the checker reads $GITHUB_EVENT_PATH, as it
# does in CI), never interpolated into a command.
#
# SELF-SCOPE: registered with no `"if"` prefilter (the rule is
# gh-scope-common.sh's) — `gh pr create` / `gh pr edit` in command position, gh bare, by
# path, or via a shell variable. Anything else -> exit 0 silently. The same
# string-match porosity gh-pr-body-guard.sh discloses applies here.
#
# Blocks a PreToolUse tool call by exiting 2 with the reason on stderr.
#
# Tests: ../tests/gh-pr-body-template-guard.test.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -r "$HERE/gitleaks-common.sh" ]]; then
	source "$HERE/gitleaks-common.sh"
else
	source "$HERE/../../git-hooks/gitleaks-common.sh"
fi

# The "gh in command position" rule lives in gh-scope-common.sh (one
# definition for every PR hook). Missing -> BLOCK, as for a missing jq: an
# unscoped fail-closed guard must not guess.
[[ -r "$HERE/gh-scope-common.sh" ]] || {
	gl_block "PR-template-guard BLOCKED: gh-scope-common.sh is missing" \
		"Expected beside this hook: $HERE/gh-scope-common.sh" \
		"Without it the guard cannot decide which commands publish a PR." \
		"Reinstall the estate-hooks plugin."
	exit 2
}
source "$HERE/gh-scope-common.sh"

CHECKER="$HERE/pr-body-check.py"
TEMPLATE_REL=".github/pull_request_template.md"
MARKER="<!-- pr-body:v1 -->" # the estate template's first line; the checker's own constant

# block <title> [line ...] — emit a formatted gl_block to stderr and BLOCK (exit 2).
block() {
	gl_block "$@"
	exit 2
}

# ---------------------------------------------------------------------------
# Parse the tool payload. jq is required; missing jq is fail-closed.
# ---------------------------------------------------------------------------
command -v jq >/dev/null 2>&1 || block \
	"PR-template-guard BLOCKED: jq is not installed" \
	"Cannot parse the tool invocation to check the PR body against the template." \
	"This guard fails closed rather than allow an unchecked 'gh pr create'." \
	"Install:  brew install jq"

INPUT="$(cat)"
TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[[ "$TOOL_NAME" == "Bash" ]] || exit 0 # not a Bash tool call — not our concern

COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[[ -n "$COMMAND" ]] || exit 0 # nothing to check

# ---------------------------------------------------------------------------
# SELF-SCOPE — gh-scope-common.sh's normalisation and command-position
# match, the same every PR hook uses.
# ---------------------------------------------------------------------------
_scope_norm="$(gh_scope_normalize "$COMMAND")"
gh_pr_in_command_position "$COMMAND" "create|edit" || exit 0 # not a PR-publishing command

ORIG_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
[[ -n "$ORIG_CWD" ]] || ORIG_CWD="$PWD"

# Temp artifacts + one inline trap, installed up front (values filled below;
# an empty one is a suppressed no-op). Inline, as the secret guard does it.
#
# FAIL-CLOSED BY CONSTRUCTION: from here on the command IS a PR-publishing
# command, so the only exits this guard may take are 0 (checked and clean,
# or not the estate's lane) and 2 (BLOCK). Claude Code treats ANY other
# PreToolUse exit code — 1 most of all — as a non-blocking error and runs
# the tool anyway. An unexpected abort (an unbound variable under set -u,
# a killed child, a bash-3.2 quirk) would therefore let an unchecked body
# through. Found by non-author review: on bash 3.2, expanding an empty
# array under set -u aborted the verdict with exit 1 whenever the checker
# died without output. The EXIT trap converts every exit that is not 0 or
# 2 into a BLOCK naming the abort; `exit` inside an EXIT trap overrides
# the status.
EVENT=""
ERRF=""
trap 'rc=$?; rm -f "$EVENT" "$ERRF" 2>/dev/null || true
	if [[ "$rc" -ne 0 && "$rc" -ne 2 ]]; then
		gl_block "PR-template-guard BLOCKED: the guard aborted before reaching a verdict (exit $rc)" \
			"An unexpected error inside the guard is not a pass. (Fail-closed.)"
		exit 2
	fi' EXIT INT TERM

# WHERE GH RUNS (gh_scope_target_dir, gh-scope-common.sh): the resolved
# `cd <path> && ...` chain target when the command has one, else the payload
# cwd. It is where a relative --body-file resolves and whose repo's template
# applies.
BODY_CWD="$(gh_scope_target_dir "$COMMAND" "$ORIG_CWD")"

# ---------------------------------------------------------------------------
# THE TEMPLATE: the repo gh runs in. Not a repo, no template, or a template
# that is not the ESTATE's -> exit 0 (not the estate's lane; CI will not run
# the check there either). The estate's template is recognised by its FIRST
# line being exactly the marker the checker derives everything from.
# ---------------------------------------------------------------------------
REPO_ROOT="$(git -C "$BODY_CWD" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[[ -n "$REPO_ROOT" ]] || exit 0
TEMPLATE="$REPO_ROOT/$TEMPLATE_REL"
[[ -f "$TEMPLATE" ]] || exit 0
[[ -r "$TEMPLATE" ]] || block \
	"PR-template-guard BLOCKED: the PR template is unreadable" \
	"Template: $TEMPLATE" \
	"The repo carries a PR-body template but this guard cannot read it, so the" \
	"body cannot be checked. (Fail-closed.) Fix the file's permissions and retry."
# Pure bash (no head/tr): a missing coreutil must not fail this gate OPEN.
_first_line=""
IFS= read -r _first_line <"$TEMPLATE" || true
_first_line="${_first_line%$'\r'}"
[[ "$_first_line" == "$MARKER" ]] || exit 0 # a foreign template: not the estate's lane

# ---------------------------------------------------------------------------
# Fail-closed preconditions: python3 and the vendored checker.
# ---------------------------------------------------------------------------
command -v python3 >/dev/null 2>&1 || block \
	"PR-template-guard BLOCKED: python3 is not installed" \
	"The PR-body template check (pr-body-check.py) and the shell-aware body" \
	"extraction (shlex) both need python3; this guard fails closed rather than" \
	"guess." \
	"Install:  brew install python3"

[[ -r "$CHECKER" ]] || block \
	"PR-template-guard BLOCKED: the vendored checker is missing" \
	"Expected: $CHECKER" \
	"It is a byte-identical copy of dotty's .github/scripts/pr-body-check.py" \
	"(provenance in this hook's header). Without it the check cannot run." \
	"Reinstall the estate-hooks plugin."

# ---------------------------------------------------------------------------
# EXTRACT the verb and the body, shell-aware. Prints one JSON object:
#   {verb, has_body, body|null, body_file|null, indeterminate: <why>|null}
# Exit 3: a body flag with no argument.  Exit 4: the command cannot be
# tokenized.  Exit 5: the scope regex matched but no `pr create|edit` token
# pair exists (indeterminate — the fail-closed answer is BLOCK).  Exit 6: a
# quoted heredoc whose delimiter also stands alone inside the body (bash
# ends the heredoc there; the body gh gets is truncated) — BLOCK.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016  # the python source is a literal; its $( is a string, not an expansion
EXTRACT="$(printf '%s' "$COMMAND" | python3 -c '
import json, re, shlex, sys
cmd = sys.stdin.read()
# THE QUOTED-HEREDOC BODY: the default shape the harness itself uses for a
# PR body is  --body "$(cat <<EOF ... EOF)"  with the delimiter QUOTED
# (single or double quotes around EOF). Quoted, the shell expands nothing
# inside, so the body is a literal this guard can read exactly. It is taken
# from the RAW command text, not from shlex: inside a double-quoted "$(...)"
# shlex treats the body text double quotes as quote boundaries and drops
# them. The span is replaced by a placeholder before tokenizing. An UNQUOTED
# delimiter does not match and falls through to the run-time check below,
# which blocks it (expansions inside are the shell to make, not readable
# here). \x27 is the single quote: this source sits inside a bash
# single-quoted string, so the character itself cannot appear.
#
# WHERE THE HEREDOC ENDS is decided the way bash decides it: at the FIRST
# line that is exactly the delimiter (for <<-, after stripping leading
# tabs), no matter what follows. A regex that looked for the first
# delimiter line followed by the closing )" read PAST a delimiter standing
# alone mid-body, vouched for the long conforming text, and let bash hand
# gh a truncated body — the exact CI failure this guard exists to stop
# (found by non-author review). So: the first bare delimiter line ends the
# body; if the closing )" does not follow it directly (whitespace only),
# the text in between is not the body and not readable -> BLOCK (exit 6).
OPENER_RE = re.compile(
    r"""(--body|-b)[ \t]+"\$\([ \t]*cat[ \t]*<<(-?)[ \t]*([\x27"])(\w+)\3[ \t]*\n"""
)
heredoc_body = None
m = OPENER_RE.search(cmd)
if m:
    delim = m.group(4)
    dash = m.group(2) == "-"
    lines = cmd[m.end():].split("\n")
    term = None
    for idx, ln in enumerate(lines):
        if (ln.lstrip("\t") if dash else ln) == delim:
            term = idx
            break
    if term is not None:
        after = "\n".join(lines[term + 1:])
        m2 = re.match(r"""[ \t\n]*\)\"""", after)
        if m2 is None:
            # The first terminator is mid-body: bash ends the heredoc there.
            sys.stdout.write(json.dumps({"midbody_delim": delim}))
            sys.exit(6)
        body_lines = lines[:term]
        if dash:
            body_lines = [ln.lstrip("\t") for ln in body_lines]
        heredoc_body = "\n".join(body_lines)
        end = m.end() + len("\n".join(lines[:term + 1])) + 1 + m2.end()
        cmd = cmd[:m.start()] + m.group(1) + " HEREDOC_BODY_PLACEHOLDER" + cmd[end:]
try:
    toks = shlex.split(cmd)
except ValueError:
    sys.exit(4)                        # command could not be tokenized
verb = None
start = None
for i, t in enumerate(toks):
    if t == "pr" and i + 1 < len(toks) and toks[i + 1] in ("create", "edit"):
        verb = toks[i + 1]
        start = i + 2
        break
if verb is None:
    sys.exit(5)
res = {"verb": verb, "has_body": False, "body": None, "body_file": None, "indeterminate": None}
seps = {"&&", "||", ";", "|"}
i = start
n = len(toks)
while i < n:
    t = toks[i]
    if t in seps:
        break
    if t in ("--body", "-b"):
        if i + 1 >= n:
            sys.exit(3)                # flag present with no argument
        res["has_body"] = True
        res["body"] = toks[i + 1]
        i += 2
        continue
    if t.startswith("--body="):
        res["has_body"] = True
        res["body"] = t[len("--body="):]
    elif t.startswith("-b") and len(t) > 2 and not t.startswith("--"):
        v = t[2:]
        res["has_body"] = True
        res["body"] = v[1:] if v.startswith("=") else v
    elif t in ("--body-file", "-F"):
        if i + 1 >= n:
            sys.exit(3)
        res["has_body"] = True
        res["body_file"] = toks[i + 1]
        i += 2
        continue
    elif t.startswith("--body-file="):
        res["has_body"] = True
        res["body_file"] = t[len("--body-file="):]
    elif t.startswith("-F") and len(t) > 2:
        v = t[2:]
        res["has_body"] = True
        res["body_file"] = v[1:] if v.startswith("=") else v
    i += 1
# A body (or body-file path) that the shell computes at run time cannot be
# read here: a command substitution, a backtick, or a variable reference.
# (A quoted-heredoc body is a literal and is exempt: it is swapped back in
# after this check, dollars and backticks included.)
for key in ("body", "body_file"):
    v = res[key]
    if v is not None and ("$(" in v or "`" in v or "$" in v):
        res["indeterminate"] = key
if res["body_file"] == "-":
    res["indeterminate"] = "body_file"
if heredoc_body is not None and res["body"] == "HEREDOC_BODY_PLACEHOLDER":
    res["body"] = heredoc_body
sys.stdout.write(json.dumps(res))
')"
ex_rc=$?

case "$ex_rc" in
0) ;;
3) block "PR-template-guard BLOCKED: --body / --body-file has no argument" \
	"A body flag was given with no following value — the intended PR body" \
	"cannot be located or checked. (Fail-closed.)" ;;
4) block "PR-template-guard BLOCKED: the command could not be parsed" \
	"shlex could not tokenize the 'gh pr create' invocation (unbalanced" \
	"quotes?). Refusing to allow a PR whose body cannot be determined. Fix" \
	"the command's quoting and retry. (Fail-closed.)" ;;
6)
	_delim="$(printf '%s' "$EXTRACT" | jq -r '.midbody_delim // "EOF"')"
	block "PR-template-guard BLOCKED: the heredoc delimiter appears inside the PR body" \
		"The body is a quoted heredoc ending at '$_delim', but a line equal to" \
		"'$_delim' stands alone INSIDE the body. bash ends the heredoc at the" \
		"FIRST such line, so gh would receive a truncated body (everything" \
		"after that line is lost) and this guard cannot vouch for what remains." \
		"Choose a delimiter that does not appear in the body on its own line," \
		"or write the body to a file and pass --body-file <path>." \
		"This is the same check CI runs; fix the body before \`gh pr create\`"
	;;
5) block "PR-template-guard BLOCKED: the PR subcommand could not be determined" \
	"The command looks like a 'gh pr create' / 'gh pr edit' but its tokens do" \
	"not carry a 'pr create' or 'pr edit' pair, so the body cannot be" \
	"located. (Fail-closed.) Write the command plainly and retry." ;;
*) block "PR-template-guard BLOCKED: body extraction failed" \
	"The tokenizer exited $ex_rc unexpectedly — refusing to proceed" \
	"unchecked. (Fail-closed.)" ;;
esac

VERB="$(printf '%s' "$EXTRACT" | jq -r '.verb')"
HAS_BODY="$(printf '%s' "$EXTRACT" | jq -r '.has_body')"
INDET="$(printf '%s' "$EXTRACT" | jq -r '.indeterminate // empty')"
BODY_FILE="$(printf '%s' "$EXTRACT" | jq -r '.body_file // empty')"

if [[ "$HAS_BODY" != "true" ]]; then
	# edit with no body flag: nothing to check.
	[[ "$VERB" == "edit" ]] && exit 0
	block "PR-template-guard BLOCKED: 'gh pr create' with no PR body" \
		"No --body / --body-file was given (a --fill, --fill-first, -f, --web," \
		"or an interactive create). The estate's PR template requires the" \
		"'<!-- pr-body:v1 -->' marker as the FIRST line and every template" \
		"section filled; gh's own fill never produces that, so CI would reject" \
		"the PR. Write the body from $TEMPLATE_REL and pass it with" \
		"--body-file <path> (or --body \"<text>\")." \
		"This is the same check CI runs; fix the body before \`gh pr create\`"
fi

if [[ -n "$INDET" ]]; then
	block "PR-template-guard BLOCKED: the PR body is computed at run time" \
		"The $INDET argument contains a command substitution, a backtick, a" \
		"variable reference, an UNQUOTED heredoc delimiter (<<EOF), or is '-'" \
		"(stdin), so this guard cannot read the body gh will publish." \
		"(Fail-closed: an unreadable body is not a pass.)" \
		"Write the body to a file first, then pass --body-file <path>, or use" \
		"--body \"\$(cat <<'EOF' ... EOF)\" with the delimiter QUOTED." \
		"This is the same check CI runs; fix the body before \`gh pr create\`"
fi

# The body text: inline, or the body file's contents (resolved where gh runs).
if [[ -n "$BODY_FILE" ]]; then
	case "$BODY_FILE" in
	/*) BODY_PATH="$BODY_FILE" ;;
	*) BODY_PATH="$BODY_CWD/$BODY_FILE" ;;
	esac
	[[ -f "$BODY_PATH" && -r "$BODY_PATH" ]] || block \
		"PR-template-guard BLOCKED: --body-file / -F path is unreadable" \
		"Referenced: $BODY_FILE" \
		"Resolved:   $BODY_PATH" \
		"gh would read this file as the PR body, but it does not exist or is" \
		"not readable from here, so its contents cannot be checked." \
		"Fail-closed: fix the path (or run from where it resolves) and retry."
	BODY="$(cat "$BODY_PATH")"
else
	BODY="$(printf '%s' "$EXTRACT" | jq -r '.body // empty')"
fi

# ---------------------------------------------------------------------------
# RUN THE CHECKER exactly as CI does: the body in a JSON event file at
# $GITHUB_EVENT_PATH, the template by path. Written with jq --arg — the
# body is data and is never interpolated into a command.
# ---------------------------------------------------------------------------
EVENT="$(mktemp)"
ERRF="$(mktemp)"
jq -n --arg body "$BODY" '{pull_request: {body: $body}}' >"$EVENT" 2>/dev/null || block \
	"PR-template-guard BLOCKED: could not write the event payload" \
	"The body could not be handed to the checker. (Fail-closed.)"

# THE CHECKER'S EXIT CODE IS THE VERDICT: 0 passes; 1 blocks quoting its
# lines; ANY other code — 2 (could not run), a kill signal (137/143), a
# crash, with or without output — blocks naming "did not complete". rc is
# captured explicitly so no shell option can abort between the call and
# the verdict, and the message lines are read into a plain string (never
# an array: an empty array expands as an unbound variable on bash 3.2 under
# set -u — the abort the EXIT trap above now also catches).
rc=0
GITHUB_EVENT_PATH="$EVENT" python3 "$CHECKER" --template "$TEMPLATE" >/dev/null 2>"$ERRF" || rc=$?

CHECKER_OUT="(the checker printed nothing)"
if [[ -s "$ERRF" ]]; then
	CHECKER_OUT="$(cat "$ERRF")"
fi
# gl_block prints one argument per line; split the checker's text on newlines
# by hand (mapfile is bash 4). The list always has at least one element.
checker_lines() {
	local rest="$CHECKER_OUT" line
	while :; do
		line="${rest%%$'\n'*}"
		printf '%s\0' "$line"
		[[ "$rest" == *$'\n'* ]] || break
		rest="${rest#*$'\n'}"
	done
}

case "$rc" in
0) exit 0 ;;
1)
	while IFS= read -r -d '' line; do
		set -- "$@" "$line"
	done < <(checker_lines)
	block "PR-template-guard BLOCKED: the PR body does not follow the template" \
		"Template: $TEMPLATE" \
		"" \
		"$@" \
		"" \
		"This is the same check CI runs; fix the body before \`gh pr create\`"
	;;
*)
	while IFS= read -r -d '' line; do
		set -- "$@" "$line"
	done < <(checker_lines)
	block "PR-template-guard BLOCKED: the template check did not complete (exit $rc)" \
		"Checker:  $CHECKER" \
		"Template: $TEMPLATE" \
		"The checker exited $rc — a crash, a kill signal (137/143), or 'could not" \
		"run' (2) — so the body was NOT checked. Its output, if any:" \
		"$@" \
		"A checker that did not complete is not a pass. (Fail-closed.)" \
		"This is the same check CI runs; fix the body before \`gh pr create\`"
	;;
esac
# Not reached: every branch above exits. The EXIT trap blocks anything else.
# shellcheck disable=SC2317  # a deliberate backstop, unreachable by design
exit 2
