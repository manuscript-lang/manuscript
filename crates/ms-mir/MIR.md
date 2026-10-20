# MIR design notes

For the HIR→MIR lowering thread. Source of truth is `src/ir.rs` (ops), `src/verify.rs` (rules), `tests/fixtures/*.mir` and `crates/ms-clif/kernels/*.mir` (examples). The text format is the fixture format.

## Shape
- Monomorphic SSA/CFG; blocks take parameters instead of phis. Types are interned in `Module::types`.
- Entry is `entry @fn`; functions return one value (aggregates are flattened to leaves by the backend).
- Locations are `!file:line:col` suffixes; `file N "path"` declares files. Backends use them for fault traces and profiles.

## Ownership (linear)
- Every value is `Own` or `Borrow`. Owned values must be consumed exactly once: passed to an `Own` parameter, stored, returned, or `drop`ped. The verifier runs move/live-set dataflow and rejects leaks, double use and use-after-move.
- Value semantics: `copy` duplicates deeply (lowering inserts it where Manuscript copies); records/lists are not aliased. Only `Shared[T]` (`shared.new`/`shared.get`) is reference counted.
- Constructors and mutators (`rec.set`, `list.push`, `list.set*`) take and return the owned aggregate; `load`/`list.get`/field reads yield borrows of the container.
- `move.out` takes ownership of a borrowed field or element without copying it; the update that follows must put a value back with `rec.fill` or `list.fill`, which store without dropping the (moved-out) old value. Lowering uses the pair so `r.items.append(x)` and `xs[i].m()` change the field in place instead of copying it.
- `drop` / `drop_if` release a value; the backend generates drop glue per type. Faults do not unwind: `cleanup.push/run` register thunks run in LIFO order before exit.

## Layout (backend contract)
- Scalars are `int`(i64), `float`(f64), `bool`(i8). Records and alternatives are flattened to scalar leaves in SSA and laid out at natural alignment in memory.
- Directly recursive types are boxed (heap pointer); others inline. `Optional[T]` of a pointer-like `T` is a nullable pointer; interface values are `{data, vtable}` with vtable slot 0 = drop glue.
- Lists are `{ptr,len,cap}`; `list.addr` and `ptr.field` expose element and field addresses for scalar-replaced loops.
- `func.addr` yields the address of a function as a `ptr`, for runtime entry points that take a callback (the comparator thunk of `List.sorted`).

## Checked arithmetic and faults
- `*.chk` ops fault on overflow/zero; plain ops wrap. Index and unwrap faults are cold blocks calling `msrt_*fault*`.
- Loop back edges carry a cancellation poll (`poll`); recursive functions bracket the body with `depth.enter/leave`.

## Optimizer contract (`src/opt`)
Passes must preserve faults and their order, ownership linearity (re-run the verifier), and polls on back edges. `optimize(&mut Module, Level, verify)` is the entry point; native tests run every fixture unoptimized and optimized against the interpreter.
