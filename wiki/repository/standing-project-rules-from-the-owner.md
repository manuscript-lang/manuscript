[Wiki](../index.md) › [Repository maintenance](index.md)

# Standing project rules from the owner

Decision (Chinmay): these rules apply to every PR and thread. Each line points to the page or doc that owns the detail.

- PRs: open ready for review, never as drafts, with squash auto-merge on; the owner does not review ([create-pr](../../skills/create-pr/SKILL.md#merging)).
- Platform parity: Linux, macOS and Windows stay at parity. Never skip, gate or no-op a test on a platform without asking the owner ([why Windows needs a dispatch](pr-checks-skip-windows-so-dispatch-the-full-matrix.md)).
- Stack PRs and cut idle time: start the next slice on the open branch (base it on the previous PR's branch, retarget to `main` when it merges) instead of waiting for gates or CI; a failure found later is fixed on the branch that owns it and merged forward.
- Cross-platform fixes: a speed fix should work on every platform, not only Linux epoll: check that a scheduler, reactor or server change has a kqueue (macOS) and IOCP via mio (Windows) path. Measuring on Linux is enough.
- Workarounds: each gets an issue naming its removal condition, and is deleted once the real fix is on `main`.
- Manuscript first: behavior goes in stdlib `.ms`; Rust keeps small, general runtime primitives.
- Dependencies: never add a third-party crate or package without asking the owner. Prefer the Rust standard library, and replace a low-value dependency with in-house code.
- Memory model: one owner per value, no refcounting, no implicit copies, borrow by default, `.clone()` the only copy, scalars always copy ([references](../../documentation/core-language/types/references.md), [lending](../language/results-borrow-parts-of-their-arguments-without-a-marker.md)). Rebase on `main` before merging and update old reference usages.
- Issues: add the `in progress` label before fixing one, remove it when the fixing PR merges, and close every issue it fixes, verifying each ([fix-issue](../../skills/fix-issue/SKILL.md)).
- No hacky fixes: [fix the root cause](fixes-address-the-root-cause-not-a-name-or-shape.md).
- `main` stays green: fix a red `main` before merging more, and merge `main` into open branches before queueing them.
- Stdlib externs live in internal modules, with no `...` stubs; types carry methods instead of getter functions. Go parity means the same outcome in an idiomatic Manuscript way, not a 1:1 API.
- Prefer hardening and polish over new features; a new module gets a fuzz pass ([bug-bash](../../skills/bug-bash/SKILL.md)).
- Linux binaries need only libc and libm, linked against glibc 2.28 stubs, with the runtime and Rust std static; static musl only with `--static` ([details](../runtime/linux-programs-link-glibc-unless-static-is-asked.md)).
- Threads: keep cross-thread state minimal and avoid complex locking. Only a few things cross a thread boundary; everything else runs on one thread ([workers](../runtime/worker-threads-are-isolates-that-share-nothing.md)).
- No comparison tables: do not put tables comparing Manuscript with Go, Python, Node, Rust or any other language or API in docs, wiki, READMEs or proposals (for example Go-to-Manuscript API mappings). Give idiom guidance as plain prose. Dated benchmark result pages under `bench/` stay as measurement evidence.

Apply when: starting any task or opening any PR.
Verify: the PR is non-draft with auto-merge, adds no `Cargo.toml` dependency, and skips no platform, and adds no language-comparison table.
