[Wiki](../index.md) › [Compiler](index.md) › C lowering of extern natives grows slice by slice

# C lowering of extern natives grows slice by slice

Verified: a call of a bodiless `extern fn` (`msstd_*`, `msrt_*`) lowers through the ms-sig table: `lower_extern.c` finds the function by its own symbol and calls `lb_native_call`, the same path native methods take. An `extern type` is a runtime object (`obj Name`). `lx_call` declines a call whose marshalled result is not the declared type, so nothing lowers to a call that yields void. Net, HTTP, fs and process stdlib functions mostly still stay with Rust because `ln_marshal` declines three shapes, each needing Rust's exact MIR (`crates/ms-lower/src/rtcall.rs`):

- A trailing `ErrSlot`: `status = call; status & 255 == 0` selects `Result.ok`, else `Result.error` over the shared `status_error` helper function (one per error type, status table, domain; see the fallible-native page).
- `HasRaw` pairs: an `Optional[Int]` argument flattens to `has, value`.
- A handle or value written through `out` (`*mut VecVal`, `*mut ObjCell`), and a `var` handle parameter's `take`/`put` around the call.

`lower-program-diff.sh` is the oracle: a function whose text differs from Rust fails it, so each shape lands with a stdlib function that uses it.

Apply when: lowering natives in C, or asking why a stdlib function is not lowered (`target/cmake/test/compiler/ms_lower_dump stdlib --program FILE`, then instrument `lb_unsupported`).

## Cyclic standard imports (checker)

Standard modules import each other in cycles. A std module declares its own symbols before its imports, so a module reached through a cycle already has them; otherwise its importer saw nothing and every body naming `msstd_*`, `parse_ip` or `sqrt` was "body not checked". User modules keep import-first order (their duplicate-name diagnostics depend on it). Bodies of `fn move` methods are checked like any other (the consuming-receiver skip in `body_check_methods` is gone; check-diff and facts agree with Rust). `ConnectionSink.close` still waits for the status-to-`Result` slice, since `lx_call` declines a `Void!` extern result.
