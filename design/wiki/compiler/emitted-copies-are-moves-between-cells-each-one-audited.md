[Wiki](../index.md) › [Compiler](index.md)

# Emitted copies are moves between cells, and each kind is audited

Verified (2026-11-25 audit): none of the first-party C `memcpy` calls (about 440, in `base`, `runtime`, and the compiler's own data) copies a value a program owns; they build buffers, grow arrays and encode bytes. The copies that matter are the `llvm.memcpy` and `llvm.memmove` the emitter writes into generated code. `ms emit --opt --ir` shows them; `opt -O3` removes about half, and `tools/memcpy-check.ms` keeps a per-program budget (`tools/memcpy-budget.txt`).

Justified: a wide value (more leaves than `wide_leaves`) lives in a stack cell, so a move between cells is a block copy: a record into an optional or result (`alt.new`, `opt.some`), a payload out of one (`alt.take`), a block argument on an edge, a return into `%sret`, a list element in or out. Each is the physical form of a language move.

Fixed: `x.f` on a record behind a pointer (a `var` receiver) lowered to `load T p; type.get T.f`, a copy of every leaf of `T` (112 bytes for `Lines`) to read one field. `opt_fieldload.c` turns it into `ptr.field` plus a load of the field alone, when the loaded record is read only by `type.get`, nothing writes memory in between, and the field lies in the record's image as it lies alone.

Open (not fixed): `alt.take` then `alt.new` of the same payload into a result of another type (`?` forwarding `Result[String, Error]` into `Result[String?, Error]`) emits two inverse `memmove`s of the payload through one cell, 139 of the 300 copies that survive LLVM in the benchmark programs. A text-level cancel does not work: the emitter writes each instruction into its own buffer, so a later move cannot retract an earlier one, and cancelling needs a fact about the middle value (only one use) the text does not carry. The fix is a MIR step that forwards the payload in place (a retag of the cell).

Apply when: a change adds a block copy to emitted code, or `make memcpy-check` fails.
Evidence: [opt_fieldload.c](../../../src/compiler/opt/opt_fieldload.c), [memcpy-check.ms](../../../tools/memcpy-check.ms), [a new owner takes a move or a written clone](a-new-owner-takes-a-move-or-a-written-clone-never-a-hidden-copy.md) for the language-level copy probe.
Verify: `make memcpy-check`; `ms emit bench/perf/programs/ms/ms.toml --opt --ir | grep -c llvm.memcpy`.
