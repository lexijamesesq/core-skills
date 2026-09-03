# work-lifecycle

Operator-owned Claude Code plugin marketplace for the estate's harness. Plugins live under `plugins/`; the marketplace manifest is `.claude-plugin/marketplace.json`.

Status: spike. `estate-hooks` packages the nine hook scripts and statusline that dotty registers in its settings file, to prove or refute that plugins can carry the harness. `spike-probe` is a throwaway probe and is removed when the spike closes.

```
claude plugin marketplace add lexijamesesq/work-lifecycle
claude plugin install estate-hooks@work-lifecycle
claude plugin enable estate-hooks@work-lifecycle
```

The plugin ships `defaultEnabled: false` on purpose: plugin install state is shared across Claude Code profiles on one machine, and each profile opts in with `plugin enable`.
