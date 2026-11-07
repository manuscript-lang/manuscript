[Wiki](../index.md) › [Standard-library design](index.md)

# Stdlib effects are tagged by logical capability

Decision: the owner said stdlib effect tags must follow logical pieces of functionality, not which `extern` a function happens to call. Many externs are pure (hashing, parsing, math) and some capabilities have several (`fs` has dozens), so extern names are only an audit aid.

Rule: tag an exported function with the `std.` capability a caller would be surprised by: files (`fs.read/write/delete`), network (`net.connect/listen`), processes, environment, clock and sleep, randomness, console, system facts. Add every capability the function exposes (`ulid` reads random bits and the clock). Methods on handles stay untagged: the capability was charged where the handle was opened. Pure parsing, formatting, math, collections, concurrency scheduling and test assertions have no tag. `// ms: effect` on a function hides its body, so a wrapper that declares one must list everything it uses.

Apply when: adding or changing an exported stdlib function that reaches the host, or a new capability. Audit method: for each module list exported functions with no tag that reach host externs through the call graph (`ms inspect` calls and entities), then judge each by what it does, not by the extern name.

Evidence: `crates/ms-tooling/tests/stdlib_effects.txt` lists every declared tag and `stdlib_effects.rs` fails on drift and on names outside the vocabulary; [proposal](../../proposals/function-effects.md).
Verify: `cargo test -p ms-tooling --test it stdlib_effects`; regenerate with `UPDATE_SNAPSHOTS=1` after a reviewed change.
