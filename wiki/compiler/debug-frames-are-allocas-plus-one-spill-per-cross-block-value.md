[Wiki](../index.md) › [Compiler and build](index.md)

# Debug frames are allocas plus one spill per cross-block value

Verified (2026-11-23, Debug build, x86-64, `llc -O0`): a frame is the emitter's allocas plus one spill slot for every SSA value live across a block or call, because the fast register allocator never colors or reuses spills and StackColoring does not run at -O0. `stdlib/toml.ms` `read_value` measured 11.6 KB: 5.1 KB of allocas (slots 2.9, call argument copies 1.0, result areas 0.9) and the rest spills (about 500 cross-block values, 286 of them loads). The 20000-deep TOML nesting test needs at most 13.4 KB per level in the 256 MB stack region.

The emitter shares storage itself, since LLVM will not at -O0: call result areas are one `%R` per function, argument copies are shared for MIR calls whose result is not `ret_borrowed` (a view result can point into an argument copy), and a `slot` confined to one block (`mir_confined_slots`, defined in that block) takes the `%cellK` of its rank in the block, so blocks share cells. Apply when: adding an alloca to `emit_frame_slots`. Verify: `ms test e2e/stdlib/toml.ms` at -O0. Not done: cross-block values still spill one slot each; coloring them or rematerializing slot addresses is the next lever (#6446). `llc -O1` halves frames but leaves the size to LLVM, so no build selects it.
