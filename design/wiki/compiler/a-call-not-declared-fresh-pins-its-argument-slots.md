[Wiki](../index.md) › [Compiler and build](index.md)

# A call not declared fresh pins its argument slots

Verified 2026-11-16: a runtime call passes a by-value `String` or list by address, and an inline text keeps its bytes inside that value, so a view of it points into the argument's slot. Pinning that slot used to be opt-in (`// ms: borrows`, one function had it), so `String.view`, the `trim` views and `Bytes.view` relied on the slot happening to survive. `Module::pins_argument_slots` now pins the slots of every call whose result holds a pointer (`needs_drop`) unless the function is declared `// ms: fresh`; a number or flag result never pins.

Cost measured on four programs (json, codecs, regex-search, image-codecs, `objdump` frame sizes): 0 to 0.5% more frame. Declaring `fresh` on a function that returns its own allocation is how a hot call gets its coloring back; never declare it for a result that can point into an argument.

A runtime function that keeps a pointer argument after it returns (a cleanup entry, a task argument) declares `// ms: retains` (`msrt_cleanup_push`, `msrt_guard_call`, `msrt_task_spawn`, `msrt_promise_defer`); `ExternDef.retains` pins its slots through `Module::pins_slot_argument`, and the LLVM lifetime scan has no name list any more. The five views (`String.view`, three `trim` views, `Bytes.view`) now declare `borrows`. Frame total over fifteen benchmarks changed by +112 bytes; instruction counts within 1%.

Apply when: adding a runtime function that returns text, bytes or a list, or a view of its argument, or one that stores a pointer it was given.
Evidence: `pin_tests` in `crates/ms-mir/src/ir/module.rs`; the corpus passes under LLVM and Cranelift with `MS_POISON_SLOTS=1`. Direction and next stages: `design/proposals/mir-owns-slot-lifetimes.md`.
