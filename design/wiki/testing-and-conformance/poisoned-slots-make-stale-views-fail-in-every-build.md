[Wiki](../index.md) › [Testing and conformance](index.md)

# Poisoned slots make a stale view fail in every build

Verified 2026-11-16: whether a pointer into a dead stack slot misbehaves depends on what the backend reuses the slot for. The split-in-frame bug (#4284) showed `[:]` only in LLVM Release; Debug passed, and valgrind or ASan cannot see it (the stack memory is valid). `MS_POISON_SLOTS=1` fills each slot with `0xDD` where its use ends (volatile `memset` before `lifetime.end`, since a plain store would be dead; `src/compiler/emit/emit_slot_pool`, `mir_slot_scope.c`), so the stale read faults or prints garbage deterministically. The corpus passes with it on (`make poison-check`); a pass means no confined slot is read after its end.

Why a build option: the fill changes the code, so it is in `BuildOptions` and the cache key.

Apply when: changing slot lifetimes in `src/compiler/emit` or `mir_slot_scope.c`, adding a runtime function whose result may point into its argument, or debugging output that differs between Debug and Release.
Evidence: `MS_POISON_SLOTS=1 ms test --build-type Release tests/conformance/fixtures/e2e/accept/split-in-frame.ms` fails loudly on a checkout without the #4285 fix.

Valgrind on compiled programs (verified 2026-11-17, release build): a program that never leaves the main task runs clean (`bench/perf/string-lines`); one that switches task stacks (`regex-search`) reports hundreds of invalid writes and uninitialised reads inside `publish_region` and `switch_away`, because the runtime maps and switches its own stacks. A valgrind nightly needs a runtime mode without stack switching first; until then it only covers single-task programs and adds nothing over poison mode.

`tools/view-matrix.ms` (`make view-matrix`, nightly) generates 420 programs: view operation x way of holding the text x temporaries after the view (including branch and loop blocks, which is where slots share storage). Negative control (verified 2026-11-17): with argument-slot pinning switched off it fails 36 programs, all `split` views in Release; unmodified it passes. A new view-returning operation belongs in its `operations()` table.

Temporaries are shared by construction (verified 2026-11-17): the emitter starts a spill or result temporary's lifetime where it is made and ends it at the end of its MIR block, and which MIR `slot`s are block-confined is a MIR fact (`mir_slot_scope.c`: every mention in one block, no escaping use, first access a write), so no text scan classifies those. The claim that a temporary dies with its MIR block failed once: a call result that a `put` moves into a variable keeps its memory as the variable's, and 74 fixtures failed while a debug-build corpus run of the same change passed. Run `make poison-check` with a freshly built `ms` (a stale one fails unrelated fixtures), and after a change to slot sharing run it with the full corpus, not only Debug. Measured (Rust era): frame bytes over fifteen benchmarks +0.07% (Release) and +0.015% (Debug).
