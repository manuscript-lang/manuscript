[Wiki](../index.md) › [Tooling and docs](index.md)

# User tooling must work in the shipped binary

Decision: documentation generation was requested as an `ms` subcommand for users, rather than only a repository generator. Native builds were requested to work from the installed `ms` alone. Native linking uses pinned `lld` and embedded runtime/support archives; do not claim a stronger installation guarantee than the packaged check demonstrates. OS-specific prerequisites remain permitted.

Verified: a PID or counter makes a staging name distinct, but does not establish ownership. Exclusively create each staging file or directory, retain existing candidates, and clean up only owned paths: shared stages can pair one build's manifest with another executable, while stale file links can overwrite unrelated targets. Exercise [runtime extraction](../../crates/ms-cli/src/engine/runtime.rs), [support extraction](../../crates/ms-clif/src/link/lld/tests.rs), and [cache publication](../../crates/ms-build/src/cache.rs) with overlapping attempts and stale links.

Apply when: adding CLI tooling, upgrading the editor client, or making claims about installation requirements.
Evidence: [client setup](../../extensions/vscode/extension.js), [dependency pin](../../extensions/vscode/package-lock.json), [activation/restart regression](../../extensions/vscode/tests/extension.test.js), [packaging script](../../tools/package.ms), [packaged binary check](../../tools/dist-check.ms), [native build contract](../../documentation/developer-tooling/how-it-works.md).
Verify: `make dist-check` extracts the archive for this host and runs the packaged binary on the hello example; additionally exercise a copied binary outside the checkout with empty caches.
