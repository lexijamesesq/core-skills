# Agent working contract

Read the maintained dotty checkout's `AGENTS.md` for the shared identity, native
checking and test-quality contract. Before authoring in a fresh clone or linked
worktree, run `${DOTTY_CHECKOUT:-$HOME/bin/dotty}/scripts/prepare-checkout.sh` with
this checkout path. Codex invokes it and estate Git/GitHub commands through
`~/.config/op-agent/bin/estate-codex --mode estate -- <command>`, using `"$APP_GH"`
inside its child shell for API operations. Claude uses its enrolled profile;
session-init calls the same helper. Missing setup is incomplete, never permission
to bypass hooks or use another actor.

For estate-hook changes run the affected `plugins/estate-hooks/tests/*.test.sh`
suites through `bash plugins/estate-hooks/tests/lib/fixture-env.sh bash <suite>`. Native push entries separately select Linear Python, estate-hook behavior, plugin validation, shared copies and packaged isolation. Keep `DOTTY_CHECKOUT` on the maintained reviewed source for shared-copy checks; the scheduled current-main drift observation remains a separate duty. Validate the Claude plugin with `claude plugin validate --strict .` when
its manifest or registration changes. Keep the standalone and shared-helper drift
checks distinct; their source commands are `.github/scripts/standalone-check.sh`
and `.github/scripts/drift-check.sh`. Do not run unrelated product suites during
checkout preparation. Clear inherited Git routing in disposable fixture tests.
