#!/usr/bin/env bash
# Test suite for estate-hooks/hooks/pr-verdict-watch-arm.sh
#
# Covers:
#   - Fires on a real `gh pr create` whose output carries a PR URL: emits
#     valid JSON additionalContext naming the PR number, repo, URL, and the
#     arm-a-Monitor instruction with a gh-pr-view poll command.
#   - Subagent branch: when agent_id is present, emits the "report the PR URL
#     first" instruction and NOT a Monitor command.
#   - Self-scope + fail-open: no-ops (no output, exit 0) for a non-Bash tool,
#     a command that only mentions `gh pr create`, a `gh pr create` with no PR
#     URL in the output (e.g. --help / failure), a non-create gh command, and
#     malformed / empty input.
#   - Never blocks: always exits 0.
#
# The hook reads a Claude Code PostToolUse payload on stdin and writes JSON on
# stdout. No network: every case is a synthetic payload. Run: bash this-file.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"

HOOK="${HOOK:-${SCRIPT_DIR}/../hooks/pr-verdict-watch-arm.sh}"
[[ -f "$HOOK" ]] || { echo "FATAL: $HOOK not found"; exit 2; }

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required for these tests"; exit 2; }

PR_URL="https://github.com/lexijamesesq/probe-local-to-merged/pull/123"

# fire <stdin-json> -> sets RC (exit code), OUT (stdout), CTX (additionalContext or "")
fire() {
    local json="$1"
    RC=0
    OUT="$(printf '%s' "$json" | bash "$HOOK" 2>/dev/null)" || RC=$?
    if [[ -n "$OUT" ]]; then
        CTX="$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)"
    else
        CTX=""
    fi
}

# A well-formed create payload. $1 = optional agent_id (empty = main branch).
# The tool_response deliberately carries a decoy PR URL before the real one to
# prove the extractor takes the created PR's URL, not merely the first match.
create_payload() {
    local agent="$1" base
    base="$(jq -nc --arg url "$PR_URL" '
        {tool_name:"Bash",
         tool_input:{command:"cd repo && gh pr create --title T --body-file body.md"},
         tool_response:("noise\nhttps://github.com/o/r/pull/1 decoy\n" + $url + "\n")}')"
    if [[ -n "$agent" ]]; then
        printf '%s' "$base" | jq -c --arg a "$agent" '. + {agent_id:$a, agent_type:"Explore"}'
    else
        printf '%s' "$base"
    fi
}

# === Main branch: fires and emits an arm-a-Monitor paragraph ===
section "Main branch (no agent_id): arms a Monitor"
fire "$(create_payload "")"
assert_eq "exits 0" "0" "$RC"
if printf '%s' "$OUT" | jq -e . >/dev/null 2>&1; then
    pass "stdout is valid JSON"
else
    fail "stdout is valid JSON" "got: $OUT"
fi
HEN="$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null)"
assert_eq "hookEventName is PostToolUse" "PostToolUse" "$HEN"
[[ -n "$CTX" ]] && pass "additionalContext present" || fail "additionalContext present" "empty"
case "$CTX" in
    *"PR #123"*) pass "names the PR number" ;;
    *) fail "names the PR number" "not in context" ;;
esac
case "$CTX" in
    *"lexijamesesq/probe-local-to-merged"*) pass "names the repo" ;;
    *) fail "names the repo" "not in context" ;;
esac
case "$CTX" in
    *"$PR_URL"*) pass "includes the PR URL" ;;
    *) fail "includes the PR URL" "not in context" ;;
esac
case "$CTX" in
    *"gh pr view"*"--json reviews,comments,state,url"*) pass "carries the gh-pr-view poll command" ;;
    *) fail "carries the gh-pr-view poll command" "not in context" ;;
esac
# The auto-mode-allow-listed primitive, never gh api.
case "$CTX" in
    *"gh api"*) fail "poll avoids gh api (not allow-listed)" "gh api present" ;;
    *) pass "poll avoids gh api (not allow-listed)" ;;
esac
case "$CTX" in
    *"N=123"*) pass "poll command is pre-filled with the PR number" ;;
    *) fail "poll command is pre-filled with the PR number" "N=123 absent" ;;
esac
case "$CTX" in
    *persistent*) pass "instructs a persistent Monitor" ;;
    *) fail "instructs a persistent Monitor" "no persistent hint" ;;
esac
# The embedded watch command must itself be syntactically valid bash.
WATCH="$(printf '%s' "$CTX" | sed -n "/^R='lexijamesesq/,/^done$/p")"
if [[ -n "$WATCH" ]] && bash -n <(printf '%s\n' "$WATCH") 2>/dev/null; then
    pass "embedded watch command parses as valid bash"
else
    fail "embedded watch command parses as valid bash" "bash -n failed"
fi

# === Subagent branch: agent_id present ===
section "Subagent branch (agent_id present): report URL first"
fire "$(create_payload "agent-abc123")"
assert_eq "exits 0" "0" "$RC"
[[ -n "$CTX" ]] && pass "additionalContext present" || fail "additionalContext present" "empty"
case "$CTX" in
    *"first line"*|*"FIRST LINE"*) pass "tells the subagent to report the URL first" ;;
    *) fail "tells the subagent to report the URL first" "not in context" ;;
esac
case "$CTX" in
    *"$PR_URL"*) pass "includes the PR URL" ;;
    *) fail "includes the PR URL" "not in context" ;;
esac
# A subagent must NOT be told to arm a doomed Monitor.
case "$CTX" in
    *"gh pr view"*) fail "subagent branch does NOT emit a Monitor command" "poll present" ;;
    *) pass "subagent branch does NOT emit a Monitor command" ;;
esac

# === Self-scope + fail-open: cases that must emit nothing ===
section "Self-scope and fail-open (no output, exit 0)"

noop_case() { # <label> <json>
    fire "$2"
    assert_eq "$1: exits 0" "0" "$RC"
    if [[ -z "$OUT" ]]; then pass "$1: emits nothing"; else fail "$1: emits nothing" "got: $OUT"; fi
}

noop_case "non-Bash tool" \
    "$(jq -nc --arg url "$PR_URL" '{tool_name:"Read",tool_input:{file_path:"x"},tool_response:$url}')"

noop_case "command only mentions gh pr create in a string" \
    "$(jq -nc --arg url "$PR_URL" '{tool_name:"Bash",tool_input:{command:"echo \"run gh pr create next\""},tool_response:$url}')"

noop_case "gh pr create but no PR URL in output (e.g. --help/failure)" \
    '{"tool_name":"Bash","tool_input":{"command":"gh pr create --help"},"tool_response":"usage: gh pr create ..."}'

noop_case "a non-create gh command (gh pr view prints a URL)" \
    "$(jq -nc --arg url "$PR_URL" '{tool_name:"Bash",tool_input:{command:"gh pr view 123"},tool_response:$url}')"

noop_case "empty stdin" ""
noop_case "garbage stdin" "not-json-at-all"
noop_case "empty JSON object" "{}"

# tool_response as an object carrying the URL in a stdout field still fires.
section "tool_response as an object (stdout field)"
fire "$(jq -nc --arg url "$PR_URL" '{tool_name:"Bash",tool_input:{command:"gh pr create --fill"},tool_response:{stdout:($url+"\n"),stderr:"",interrupted:false}}')"
assert_eq "exits 0" "0" "$RC"
case "$CTX" in
    *"PR #123"*) pass "extracts the PR from an object tool_response" ;;
    *) fail "extracts the PR from an object tool_response" "got: $OUT" ;;
esac

# === Self-scope: command-position wrapper / env-assignment prefixes ===
# The regex allows env/time/sudo/nohup/command wrappers and leading VAR=val
# assignments before `gh pr create`. Exercise those branches (and the negative
# that `createfoo` is not the create subcommand).
section "Self-scope: wrapper/env prefixes fire; a look-alike subcommand does not"
for c in "FOO=bar gh pr create --fill" "sudo gh pr create --fill" "time env FOO=bar gh pr create --fill"; do
    fire "$(jq -nc --arg url "$PR_URL" --arg cmd "$c" '{tool_name:"Bash",tool_input:{command:$cmd},tool_response:($url+"\n")}')"
    case "$CTX" in
        *"PR #123"*) pass "fires on wrapper/env prefix: $c" ;;
        *) fail "fires on wrapper/env prefix: $c" "no context (got: $OUT)" ;;
    esac
done
fire "$(jq -nc --arg url "$PR_URL" '{tool_name:"Bash",tool_input:{command:"gh pr createfoo"},tool_response:($url+"\n")}')"
if [[ -z "$OUT" ]]; then pass "does not fire on 'gh pr createfoo'"; else fail "does not fire on 'gh pr createfoo'" "fired: $OUT"; fi

# === Embedded WATCH command executed against a stubbed gh/sleep ===
# The embedded poll loop is the highest-risk logic (dedup via the SEEN file,
# the seed-then-emit gate, the operator/Margot[bot] login match, merge-exit),
# and the cases above only prove it PARSES. Here we EXTRACT the real emitted
# command and run it against a fake `gh` whose JSON changes per poll, with a
# no-op `sleep`, over three cycles: pass 1 seeds silently, pass 2 emits exactly
# the genuinely-new matched items, pass 3 reports MERGED and exits.
section "Embedded WATCH command (stubbed gh/sleep, seed-then-emit + merge-exit)"
fire "$(create_payload "")"
WATCH="$(printf '%s' "$CTX" | sed -n "/^R='lexijamesesq/,/^done\$/p")"
if [[ -z "$WATCH" ]]; then
    fail "extract WATCH command from hook output" "empty — the emitted paragraph shape changed"
else
    STUB="$(mktemp -d)"
    cat > "$STUB/pass1.json" <<JSON
{"state":"OPEN","url":"$PR_URL","reviews":[{"id":"r1","author":{"login":"alice"},"state":"APPROVED"}],"comments":[{"id":"c1","author":{"login":"lexijamesesq"}},{"id":"c2","author":{"login":"margot-the-meticulous[bot]"}},{"id":"c3","author":{"login":"randomuser"}}]}
JSON
    cat > "$STUB/pass2.json" <<JSON
{"state":"OPEN","url":"$PR_URL","reviews":[{"id":"r1","author":{"login":"alice"},"state":"APPROVED"},{"id":"r2","author":{"login":"margot-the-meticulous"},"state":"CHANGES_REQUESTED"}],"comments":[{"id":"c1","author":{"login":"lexijamesesq"}},{"id":"c2","author":{"login":"margot-the-meticulous[bot]"}},{"id":"c3","author":{"login":"randomuser"}},{"id":"c4","author":{"login":"lexijamesesq"}}]}
JSON
    cat > "$STUB/pass3.json" <<JSON
{"state":"MERGED","url":"$PR_URL","reviews":[],"comments":[]}
JSON
    cat > "$STUB/gh" <<'GH'
#!/usr/bin/env bash
n=$(cat "$FAKE_CNT" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$FAKE_CNT"
if [[ "$1" == "pr" && "$2" == "view" ]]; then
    case "$n" in 1) cat "$FAKE_DIR/pass1.json" ;; 2) cat "$FAKE_DIR/pass2.json" ;; *) cat "$FAKE_DIR/pass3.json" ;; esac
fi
exit 0
GH
    printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/sleep"
    chmod +x "$STUB/gh" "$STUB/sleep"
    TO=""; command -v timeout >/dev/null 2>&1 && TO="timeout 20"
    WOUT="$(FAKE_CNT="$STUB/cnt" FAKE_DIR="$STUB" PATH="$STUB:$PATH" $TO bash -c "$WATCH" 2>/dev/null)"; WRC=$?
    assert_eq "WATCH exits 0 after MERGED" "0" "$WRC"
    case "$WOUT" in *"margot-the-meticulous (CHANGES_REQUESTED)"*) pass "emits the new Margot review (pass 2)" ;; *) fail "emits the new Margot review (pass 2)" "got: $WOUT" ;; esac
    case "$WOUT" in *"new comment by lexijamesesq"*) pass "emits the new operator comment (pass 2)" ;; *) fail "emits the new operator comment (pass 2)" "got: $WOUT" ;; esac
    case "$WOUT" in *randomuser*) fail "excludes an unmatched-login comment" "randomuser leaked into output" ;; *) pass "excludes an unmatched-login comment" ;; esac
    case "$WOUT" in *alice*) fail "seed pass is silent (no re-emit of seeded items)" "alice (seeded) re-emitted" ;; *) pass "seed pass is silent (no re-emit of seeded items)" ;; esac
    case "$WOUT" in *MERGED*) pass "emits terminal MERGED line" ;; *) fail "emits terminal MERGED line" "got: $WOUT" ;; esac
    rm -rf "$STUB"
fi

finish
