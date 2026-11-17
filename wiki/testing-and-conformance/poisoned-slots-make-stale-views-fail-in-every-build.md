[Wiki](../index.md) › [Testing and conformance](index.md)

# Poisoned slots make a stale view fail in every build

Verified 2026-11-16: whether a pointer into a dead stack slot misbehaves depends on what the backend reuses the slot for. The split-in-frame bug (#4284) showed `[:]` only in LLVM Release; Debug and Cranelift passed, and valgrind or ASan cannot see it (the stack memory is valid). `MS_POISON_SLOTS=1` fills each slot with `0xDD` where its use ends (LLVM: volatile `memset` before `lifetime.end`, a plain store would be dead; Cranelift: word stores before the block terminator, in `slotshare`), so the stale read faults or prints garbage deterministically. The corpus passes on Cranelift with it on; a pass on LLVM means no confined slot is read after its end.

Why a build option: the fill changes the code, so it is in `BuildOptions` and the cache key.

Apply when: changing `llvm_lifetimes.rs` or `slotshare.rs`, adding a runtime function whose result may point into its argument, or debugging output that differs between Debug and Release.
Evidence: `a_poisoned_slot_is_filled_before_its_end_marker` (`llvm_lifetimes.rs`); `MS_POISON_SLOTS=1 ms test --build-type Release tests/conformance/fixtures/e2e/accept/split-in-frame.ms` fails loudly on a checkout without the #4285 fix.

Valgrind on compiled programs (verified 2026-11-17, release build): a program that never leaves the main task runs clean (`bench/perf/string-lines`); one that switches task stacks (`regex-search`) reports hundreds of invalid writes and uninitialised reads inside `publish_region` and `switch_away`, because the runtime maps and switches its own stacks. A valgrind nightly needs a runtime mode without stack switching first; until then it only covers single-task programs and adds nothing over poison mode.

`tools/view-matrix.ms` (`make view-matrix`, nightly) generates 420 programs: view operation x way of holding the text x temporaries after the view (including branch and loop blocks, which is where slots share storage). Negative control (verified 2026-11-17): with argument-slot pinning switched off it fails 36 programs, all `split` views in Release; unmodified it passes. A new view-returning operation belongs in its `operations()` table.
