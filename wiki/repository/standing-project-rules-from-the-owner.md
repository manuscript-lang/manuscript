[Wiki](../index.md) › [Repository maintenance](index.md)

# Standing project rules from the owner

Decision (Chinmay): these rules apply to every PR and thread. Each line points to the page or doc that owns the detail.

- PRs: open ready for review, never as drafts, with squash auto-merge on; the owner does not review ([create-pr](../../skills/create-pr/SKILL.md#merging)).
- Platform parity: Linux, macOS and Windows stay at parity. Never skip, gate or no-op a test on a platform without asking the owner ([why Windows needs a dispatch](pr-checks-skip-windows-so-dispatch-the-full-matrix.md)).
- Workarounds: each gets an issue naming its removal condition, and is deleted once the real fix is on `main`.
- Manuscript first: behavior goes in stdlib `.ms`; Rust keeps small, general runtime primitives.
- Dependencies: never add a third-party crate or package without asking the owner. Prefer the Rust standard library, and replace a low-value dependency with in-house code.
- Memory model: one owner per value, no refcounting, no implicit copies, borrow by default, `.clone()` the only copy, scalars always copy ([references](../../documentation/core-language/types/references.md), [lending](../language/results-lend-parts-of-their-arguments-without-a-marker.md)). Rebase on `main` before merging and update old reference usages.
- Linux binaries need only libc and libm, linked against glibc 2.28 stubs, with the runtime and Rust std static; static musl only with `--static` ([details](../runtime/linux-programs-link-glibc-unless-static-is-asked.md)).
- Threads: keep cross-thread state minimal and avoid complex locking. Only a few things cross a thread boundary; everything else runs on one thread ([workers](../runtime/worker-threads-are-isolates-that-share-nothing.md)).

Apply when: starting any task or opening any PR.
Verify: the PR is non-draft with auto-merge, adds no `Cargo.toml` dependency, and skips no platform.
