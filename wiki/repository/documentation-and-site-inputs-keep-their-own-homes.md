[Wiki](../index.md) › [Repository maintenance](index.md)

# Documentation and site inputs keep their own homes

Verified: authored guides live in `documentation/`, site inputs in `website/`, and Pages output is built into ignored `.artifacts/book/` and deployed as an Actions artifact. Hugo mounts the shared root version and extension grammar as assets; parent-relative `readFile` calls did not resolve those inputs. The book and API reference come from the Rust docgen (`crates/ms-tooling/src/guide`), not a checked-in HTML tree.


Apply when: relocating documentation or site inputs, or changing the publication workflow.
Evidence: [site mounts](../../website/hugo.toml), [publication checks](../../tests/docs/publication.test.cjs), [architecture](../../documentation/contributing/architecture.md).
Verify: run `make docs-check` and `make book-check`. Build `.artifacts/book/` with destination cleanup and verify the Pages artifact deployment; generated HTML is not a source commit.
