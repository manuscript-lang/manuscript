[Wiki](../index.md) › [Compiler and build](index.md)

# A call not declared fresh pins its argument slots

Verified 2026-11-16: a runtime call passes a by-value `String` or list by address, and an inline text keeps its bytes inside that value, so a view of it points into the argument's slot. Pinning that slot used to be opt-in (`// ms: borrows`, one function had it), so `String.view`, the `trim` views and `Bytes.view` relied on the slot happening to survive. `Module::pins_argument_slots` now pins the slots of every call whose result holds a pointer (`needs_drop`) unless the function is declared `// ms: fresh`; a number or flag result never pins.

Cost measured on four programs (json, codecs, regex-search, image-codecs, `objdump` frame sizes): 0 to 0.5% more frame. Declaring `fresh` on a function that returns its own allocation is how a hot call gets its coloring back; never declare it for a result that can point into an argument.

Apply when: adding a runtime function that returns text, bytes or a list, or a view of its argument.
Evidence: `pin_tests` in `crates/ms-mir/src/ir/module.rs`; the corpus passes under LLVM and Cranelift with `MS_POISON_SLOTS=1`. Direction and next stages: `proposals/mir-owns-slot-lifetimes.md`.
