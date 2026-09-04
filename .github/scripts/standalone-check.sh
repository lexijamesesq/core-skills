#!/usr/bin/env bash
# standalone-check.sh — proves the packaged copies run correctly with NO
# dotty checkout present, not merely that they are byte-identical to one.
#
# Why this exists: drift-check.sh (narrowed in the same series) only ever
# asked "does this repo's copy match dotty's?" — identity, not portability.
# Three hooks/scripts silently depended on running from INSIDE a dotty
# checkout (a repo-relative walk, or dotty's OWN repo as a zero-config
# fallback) and broke the moment they ran from this plugin's installed
# cache instead — gh-pr-body-guard.sh (blocked gh pr create outside a
# repo with its own .gitleaks.toml), gate-mechanical.sh (the /publish gate
# crashed sourcing gitleaks-common.sh), and the traffic-cone wrapper
# (couldn't find cone_preflight.py). All three were fixed in the same
# series that adds this check. This check is what proves they STAY fixed:
# run from THIS checkout alone, no dotty anywhere on the machine (this
# script never checks dotty out and never references a dotty path).
#
# Exit 0 iff every check below passes.
set -euo pipefail

WL_CHECKOUT="${1:?usage: standalone-check.sh <path-to-this-repo>}"
FAIL=0

# A real installed plugin cache has no .git anywhere in its ancestry — `git
# rev-parse --show-toplevel` from inside it fails outright. A live checkout
# of this repo (CI's own actions/checkout, or a dev clone) does NOT
# reproduce that: `git -C plugins/estate-hooks/hooks rev-parse
# --show-toplevel` walks UP and finds the checkout's OWN .git, resolving to
# a repo that (this repo tracks .gitleaks.toml at its root) would make the
# OLD, repo-dependent resolution look like it still works — silently
# testing "runs inside a plain checkout" instead of "runs from the cache."
# Strip .git entirely by copying just plugins/ to a scratch dir with none.
WL_ROOT="$(mktemp -d)"
cp -a "$WL_CHECKOUT/plugins" "$WL_ROOT/plugins"

# Fixture operator ruleset at a SYNTHETIC fixed path — same convention
# gh-pr-body-guard.test.sh already uses (XDG_CONFIG_HOME override), never
# the real machine install. Exported for every check below.
export XDG_CONFIG_HOME="$WL_ROOT/xdg"
mkdir -p "$XDG_CONFIG_HOME/gitleaks"
cat > "$XDG_CONFIG_HOME/gitleaks/operator-rules.toml" <<'EOF'
title = "standalone-check fixture operator rules (fixed path)"
[extend]
useDefault = true
EOF

trap 'rm -rf "$WL_ROOT"' EXIT

check() { # <label> <status:0|1> [detail...]
    local label="$1" status="$2"
    shift 2
    if [[ "$status" -eq 0 ]]; then
        echo "OK: $label"
    else
        echo "STANDALONE-CHECK FAIL: $label${*:+ — $*}"
        FAIL=1
    fi
}

# ---------------------------------------------------------------------------
# 1. gh-pr-body-guard.sh resolves a ruleset from a repo with NO .gitleaks.toml,
#    via the fixed-path operator ruleset — proves Path 3 no longer needs
#    dotty's own repo (or any repo at all) to supply the config.
# ---------------------------------------------------------------------------
GUARD="$WL_ROOT/plugins/estate-hooks/hooks/gh-pr-body-guard.sh"
scratch_repo="$(mktemp -d)"
git -C "$scratch_repo" init -q
echo "standalone-check scratch body, no secrets" > "$scratch_repo/body.md"
payload="$(printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"gh pr create --title standalone-check --body-file body.md"}}' "$scratch_repo")"
if [[ -x "$GUARD" ]]; then
    if printf '%s' "$payload" | bash "$GUARD" >/tmp/standalone-guard-out.$$ 2>&1; then
        check "gh-pr-body-guard.sh scans a config-less repo via the fixed-path ruleset" 0
    else
        check "gh-pr-body-guard.sh scans a config-less repo via the fixed-path ruleset" 1 \
            "$(tail -n 5 /tmp/standalone-guard-out.$$ | tr '\n' '|')"
    fi
    rm -f /tmp/standalone-guard-out.$$
else
    check "gh-pr-body-guard.sh scans a config-less repo via the fixed-path ruleset" 1 \
        "missing or not executable at $GUARD"
fi
rm -rf "$scratch_repo"

# ---------------------------------------------------------------------------
# 2. gate-mechanical.sh's gitleaks-common.sh resolver finds a copy with NO
#    ../../../../git-hooks/ sibling present — proves the estate-hooks-cache
#    fallback fires, not just the same-repo path.
#
# Needs its own scratch $HOME/.claude-*/plugins/installed_plugins.json
# fixture — the resolver's fallback globs "$HOME"/.claude-*, and this
# check must prove the FALLBACK MECHANISM works, not that it happens to
# find a real machine's real install (which a CI runner never has, and a
# dev machine has only by accident of its own local state — exactly the
# gap that let this check pass locally while failing in CI the first
# time). Points the fixture's installPath at this same scratch copy of
# plugins/estate-hooks, so the check is fully self-contained.
# ---------------------------------------------------------------------------
GATE_SCRIPTS="$WL_ROOT/plugins/work-lifecycle/skills/publish/scripts"
SCRATCH_HOME="$WL_ROOT/scratch-home"
mkdir -p "$SCRATCH_HOME/.claude-fake/plugins"
cat > "$SCRATCH_HOME/.claude-fake/plugins/installed_plugins.json" <<EOF
{"plugins": {"estate-hooks@work-lifecycle": [{"scope": "user", "installPath": "$WL_ROOT/plugins/estate-hooks"}]}}
EOF
resolver_probe="$(mktemp)"
cat > "$resolver_probe" <<EOF
set -euo pipefail
SCRIPT_DIR="/nonexistent/no/such/checkout/scripts"
$(sed -n '/^resolve_gitleaks_common()/,/^}/p' "$GATE_SCRIPTS/gate-mechanical.sh")
resolve_gitleaks_common
EOF
if resolved="$(HOME="$SCRATCH_HOME" bash "$resolver_probe" 2>/tmp/standalone-resolver-out.$$)"; then
    if [[ -r "$resolved" ]]; then
        check "gate-mechanical.sh's gitleaks-common.sh resolver falls back to the estate-hooks cache" 0
    else
        check "gate-mechanical.sh's gitleaks-common.sh resolver falls back to the estate-hooks cache" 1 \
            "resolved to $resolved, which is not readable"
    fi
else
    check "gate-mechanical.sh's gitleaks-common.sh resolver falls back to the estate-hooks cache" 1 \
        "$(cat /tmp/standalone-resolver-out.$$)"
fi
rm -f "$resolver_probe" /tmp/standalone-resolver-out.$$

# ---------------------------------------------------------------------------
# 3. traffic-cone wrapper resolves cone_preflight.py from its own sibling
#    linear/scripts, with dotty stripped from PATH entirely.
# ---------------------------------------------------------------------------
TC_WRAPPER="$WL_ROOT/plugins/work-lifecycle/skills/traffic-cone/scripts/traffic-cone"
if [[ -f "$TC_WRAPPER" ]]; then
    if PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v 'bin/dotty' | tr '\n' ':')" \
        python3 "$TC_WRAPPER" --help >/tmp/standalone-tc-out.$$ 2>&1; then
        check "traffic-cone wrapper resolves its scripts with dotty stripped from PATH" 0
    else
        check "traffic-cone wrapper resolves its scripts with dotty stripped from PATH" 1 \
            "$(tail -n 5 /tmp/standalone-tc-out.$$ | tr '\n' '|')"
    fi
    rm -f /tmp/standalone-tc-out.$$
else
    check "traffic-cone wrapper resolves its scripts with dotty stripped from PATH" 1 \
        "missing at $TC_WRAPPER"
fi

if [[ "$FAIL" -ne 0 ]]; then
    echo
    echo "STANDALONE CHECK FAILED — a packaged copy depends on something dotty"
    echo "supplies that this repo's own cache does not."
    exit 1
fi

echo
echo "All packaged copies run standalone. No dotty dependency found."
