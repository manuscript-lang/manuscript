[Wiki](../index.md) › [Tooling and docs](index.md)

# User tooling must work in the shipped binary

Decision: documentation generation was requested as an `ms` subcommand for users, rather than only a repository generator. Native builds were requested to work from the installed `ms` alone. Today linking uses the system `cc`/`ld`, and a bundled linker is a tracked follow-up ([design contract](../../crates/DESIGN.md)); do not claim a stronger installation guarantee than the packaged check demonstrates. OS-specific prerequisites remain permitted.

Apply when: adding CLI tooling, upgrading the editor client, or making claims about installation requirements.
Evidence: [client setup](../../extensions/vscode/extension.js), [dependency pin](../../extensions/vscode/package-lock.json), [activation/restart regression](../../extensions/vscode/tests/extension.test.js), [packaging script](../../tools/package.ms), [packaged binary check](../../tools/dist-check.ms), [native build contract](../../documentation/developer-tooling/how-it-works.md).
Verify: `make dist-check` extracts the archive for this host and runs the packaged binary on the hello example; additionally exercise a copied binary outside the checkout with empty caches.
