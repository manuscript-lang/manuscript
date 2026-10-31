[Wiki](../index.md) › [Standard-library design](index.md)

# One spelling per operation; consolidate by domain

Decision: the stdlib reorganization (#659) removed duplicate routes: `cli` moved into `process` (`process.arguments`, `process.control().environment()` is the only environment API), the temp-root query moved to `FileSystem.temporary_root` (`fs` is the only temp-dir API), string-typed `crypto.hmac` was dropped for `HashAlgorithm.hmac`, and the SSE decoder became an interface with `feed`/`finish`/`retry` methods. Before adding a function, search for an existing home with `ms search_symbol`; a second spelling needs a new decision. Do not restore removed names from old docs or branches.

Apply when: adding or moving a stdlib function, or when two modules could both own an operation.
The scalar `math.abs`, `abs_int`, `sign`, `sign_int` and `to_float32` functions duplicated the `.abs()`, `.sign()` and `.to_float32()` methods and were removed, as was `Set.entries()`, which only repeated `values()` as `[value, value]` pairs; `String.parse_float()` joins `parse_int()` as the Optional form while `math.parse_float` keeps the Result form with its cause.
Evidence: commit 9a2dc4e6, [process](../../stdlib/process.ms), [fs](../../stdlib/fs.ms), [crypto](../../stdlib/crypto.ms), [sse](../../stdlib/sse.ms).
Verify: `ms search_symbol <old name>` finds no declaration; `make docs-check` passes and every moved symbol has an updated fixture.

---
Topics: [Standard-library API shape](../topics/stdlib-api-shape.md)
