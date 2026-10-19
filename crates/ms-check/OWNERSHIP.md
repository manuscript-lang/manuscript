# Ownership facts

`ownership.rs` computes the facts `ms-mir` needs to elide reference-count updates. It **rejects nothing**: `crates/DESIGN.md` keeps today's reference semantics (aliasing, shallow `.clone()`, mutator chaining, closure snapshots), so there is no exclusivity or move rule to enforce, and the proposal's value-semantics checker is not built. A rejection corpus therefore does not exist; the corpus is `tests/ownership.rs`, which pins the facts. If the value-semantics decision flips, rejections would be added as a new pass over these same facts.

```rust
let ownership = program.hir().ownership();
let facts = ownership.of(&callable).unwrap();
facts.use_at(name_expr.id, &binding)   // Use { kind, last }
facts.bindings[&binding.uid]           // BindingFacts { role, retained, captured, fresh, .. }
facts.parameter_escapes                // per parameter
```

## What is computed

- **Use kind** per occurrence of a local: `Borrow` (read transiently: operands, member/index bases, interpolation, conditions, scrutinee, loop iterable), `Retain` (stored in a record/list/map, bound, returned, or passed to a parameter the callee lets escape), `Capture` (lambda snapshot at creation, a use at the lambda), `Write` (reassignment; keyed by the assignment statement).
- **Last use**: no later use of the same value on any path. Computed by backward liveness over structured control flow with loop fixpoints; `break`/`continue`/`return` use the right live sets. A read that precedes a reassignment with no read in between is last for the old value. `last` means "the value is dead", not "release here": MIR still owns scope-exit release for paths that skip the use.
- **Callee summaries**: per callable, which parameters and the receiver escape (a `Retain` or `Capture` of the parameter anywhere in the body, lambdas included). Solved to a fixpoint over the program, so recursion and mutual recursion are conservative-correct (starts optimistic, only grows).
- **Binding facts**: `role`, `uses`, `retained`, `captured`, `reassigned`, `fresh` (initialized by a literal, constructor or lambda). `local_only()` = fresh and never retained, captured or reassigned: the allocation can be scalar-replaced or stack allocated.

## Conventions and conservative choices

- Native functions and methods **borrow** all arguments (`DESIGN.md`: arguments are borrowed unless documented as consuming). A native that stores an argument takes its own count.
- Constructors retain their arguments. Dynamic dispatch (`contract`), local closures and unresolved calls retain (unknown callee).
- Closures run any number of times: inside a lambda body, captured variables are live-out and never have a last use.
- A `with` resource is live until scope exit (cleanup is the final use) and on every `return`/`break` inside the block.
- `and`/`or` right operands run on some paths only; reads in them do not hide later reads.

## Open decisions (recorded, resolved for this model)

| Decision | Resolution under reference counting |
| --- | --- |
| Projections vs copies | Projections (`a.b`, `a[i]`, payload bindings) alias; reading one is a borrow of the base and the result is retained by whoever stores it. |
| Mutator results | A mutator returns the same object (chaining); the receiver is borrowed unless the callee's summary says `self` escapes. |
| Closure escape | Captures snapshot at creation; a captured value is retained for the closure's lifetime. |
| Generic copyability | No copy rule: every value is a scalar or a counted pointer; monomorphization picks the representation. |
| Handle types | Ordinary counted objects; `with` runs cleanup at scope exit and on faults (runtime cleanup stack). |

## Known limits

Field and element places are not tracked (only locals); aliasing through a second reference is not detected, so MIR must check the runtime count for in-place updates. Native storing behavior is not modeled per function.
