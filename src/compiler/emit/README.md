# src/compiler/emit

MIR to LLVM IR text (`emit.h`). The emitter reads the in-memory `MirModule` and writes one LLVM module; the
object step in `compiler/link/object.c` hands it to the pinned `opt` and `llc`.

- `emit_leaf.c`, `emit_memory.c`: leaves, names, loads and stores. A MIR value is a run of SSA registers.
- `emit_scalar.c`, `emit_checked.c`: arithmetic, compares, checked operations that split a block into pieces.
- `emit_call.c`: calls of MIR functions and of runtime functions.
- `emit_term.c`, `emit_func.c`, `emit.c`, `emit_decl.c`, `emit_entry.c`: terminators and phis, one function, the
  module, its declarations, symbol names and the C `main`.

- `emit_record.c`, `emit_option.c`, `emit_list.c`, `emit_string.c`, `emit_data.c`: records and the one-block `if`,
  alternatives and optionals, unchecked list operations, string bytes and constant data, static data.
- `emit_closure.c`, `emit_iface.c`, `emit_task.c`: closures and indirect calls, interfaces, the cancellation poll.

- `emit_debug.c`: source places (`places`): a `!dbg` location per instruction, column = module-wide scope number.
- `emit_tables.c`: the function names and module-wide scope list the fault tables (compiler/link) need; build it
  before `emit_name_symbols`.

- `emit_hints.c`: purity (`memory(none)`) and deep-glue (`noinline`) hints, which only speed up LLVM.
