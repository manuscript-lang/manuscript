[Wiki](../index.md) › [Tooling and docs](index.md)

# Standard-library prose has the same owner as declarations

Decision: standard-library API contracts belong with their `.ms` declarations; generated Markdown is disposable and lives under `.artifacts/docs/`. Existing guide and special-call-rule comment blocks remain inputs to the generator. The later November 5 correction requires runnable library recipes, fixtures, and tutorial programs in authored documentation/example locations, not in stdlib source or comments. See [teaching direction](teach-a-runnable-path-before-formal-reference.md). Keep existing routes and do not duplicate the generated API catalog.


Reference navigation follows the source directories and filenames; compatibility aliases retain the old flat URLs and fragments, with invisible anchors for former synthetic member headings. Topic guides teach one subject: Promise waiting/cancellation belongs on Promises, stream reads/pipelines and pipe examples belong on Streams and pipes. Inherent methods must retain their API while hiding synthetic interface names; use checked synthetic identity or the original parsed impl, never a name suffix.

Apply when: changing library docs or the book pipeline.
Evidence: [docgen](../../crates/ms-tooling/src/guide/docgen.rs), [docgen binary](../../crates/ms-tooling/src/bin/ms-docgen.rs), [Makefile docs targets](../../Makefile).
Verify: `make docs-check` works without generated Markdown; `make book-check` generates the mounted pages and validates routes and downloads. Also run publication tests against the production output; redirect tests must accept its canonical origin as well as the validation origin.
