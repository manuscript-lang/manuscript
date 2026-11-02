[Wiki](../index.md) › [Tooling and docs](index.md)

# Standard-library prose has the same owner as declarations

Decision: the user requires `.ms` standard-library sources to own all library documentation. Guide and special-call-rule comment blocks ship with the sources; generated Markdown is disposable and lives under `.artifacts/docs/`. Keep existing routes when moving prose. API contracts belong with their `.ms` modules.


Apply when: changing library docs or the book pipeline.
Evidence: [docgen](../../crates/ms-tooling/src/guide/docgen.rs), [docgen binary](../../crates/ms-tooling/src/bin/ms-docgen.rs), [Makefile docs targets](../../Makefile).
Verify: `make docs-check` works without generated Markdown; `make book-check` generates the mounted pages and validates routes and downloads.
