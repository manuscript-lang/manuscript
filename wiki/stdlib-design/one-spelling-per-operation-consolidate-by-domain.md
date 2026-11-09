[Wiki](../index.md) › [Standard-library design](index.md)

# One spelling per operation; consolidate by domain

Decision: the stdlib reorganization (#659) removed duplicate routes: `cli` moved into `process` (`process.arguments`, `process.control().environment()` is the only environment API), the temp-root query moved to `FileSystem.temporary_root` (`fs` is the only temp-dir API), string-typed `crypto.hmac` was dropped for `HashAlgorithm.hmac`, and the SSE decoder became an interface with `feed`/`finish`/`retry` methods.

Round 2 (consolidation audit): `assert_*` aliases of `expect_*`, `chmod_link`/`chown_link`/`set_times_link` (now `follow_links: Bool = true` like `stat`), `system.monotonic_time` (use `time.monotonic()`) were removed; `create_link`/`read_link`/`hard_link` became `create_symlink`/`read_symlink`/`create_hard_link`; `set_identity` takes `IdentityKind`, `endianness()` returns `Endianness`; `uuid_v4` moved next to the other UUIDs in `@std/data/uuid.ms`; `Version.compare`/`Version.format` are methods. Base64 has one `base64_encode`/`base64_decode` pair with `url_safe:` and `padded:` (the `_unpadded` pair is gone). A record method named `to_string` is shadowed by the intrinsic `to_string`, so name it `format`. `net.request`/`HttpClient.request` take a `Writable` body (the `request_bytes` pair is gone). Decision (Chinmay): keep both `5.seconds()` and `seconds(5)`; do not consolidate. Deferred: the `fetch`/`HttpClient`/`request` overlap, the three integer parsers, `sha256` helpers (the lowering special-cases them), `Int` bit operations as free functions.

Apply when: adding or moving a stdlib function, or when two modules could both own an operation.
Evidence: commit 9a2dc4e6, [process](../../stdlib/os/process.ms), [fs](../../stdlib/os/fs.ms), [crypto](../../stdlib/crypto.ms), [sse](../../stdlib/net/sse.ms).
Verify: `ms search_symbol <old name>` finds no declaration; `make docs-check` passes and every moved symbol has an updated fixture.
