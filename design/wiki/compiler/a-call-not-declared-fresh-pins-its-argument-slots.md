[Wiki](../index.md) › [Compiler and build](index.md)

# A call not declared fresh pins its argument slots

Verified 2026-11-16: a runtime call passes a by-value `String` or list by address, and an inline text keeps its bytes inside that value, so a view of it points into the argument's slot. Pinning that slot used to be opt-in (`@borrows`, one function had it), so `String.view`, the `trim` views and `Bytes.view` relied on the slot happening to survive. `mir_extern_pins_argument` now pins the slots of every call whose result holds a pointer (`needs_drop`) unless the function is declared `// ms: fresh`; a number or flag result never pins.

Cost measured on four programs (json, codecs, regex-search, image-codecs, `objdump` frame sizes): 0 to 0.5% more frame. Declaring `fresh` on a function that returns its own allocation is how a hot call gets its coloring back; never declare it for a result that can point into an argument.

A runtime function that keeps a pointer argument after it returns (a task argument) is flagged `retains` on its MIR extern; `MirExtern.retains` pins its slots, and the lifetime scan has no name list any more. The five views (`String.view`, three `trim` views, `Bytes.view`) now declare `@borrows`. Frame total over fifteen benchmarks changed by +112 bytes; instruction counts within 1%.

Apply when: adding a runtime function that returns text, bytes or a list, or a view of its argument, or one that stores a pointer it was given.
Evidence: `mir_extern_pins_argument` (`src/compiler/mir/mir_pass.h`) and `mir_slot_scope.c`; the corpus passes with `make poison-check`. Direction and next stages: `design/proposals/mir-owns-slot-lifetimes.md`.
