# Ownership (value semantics)

`Hir::ownership()` enforces the value-semantics memory model of `crates/DESIGN.md` (decision 1) and exposes the moves, drops and borrows lowering needs. It is opt-in for diagnostics (`CheckOptions.ownership`, `ms-check-dev --ownership`); it runs only on programs that already type check.

```rust
let own = program.hir().ownership();
own.diagnostics                       // rejections
let f = own.of(&callable).unwrap();   // CallableOwnership
f.use_at(name_expr.id, &binding)      // Use { access: Copy|Borrow|Mutate|Move|Write, last }
f.bindings[&binding.uid]              // BindingFacts { role, class, owned, borrows }
f.calls[&call.id]                     // CallModes { receiver, arguments, returns_receiver, .. }
f.lambdas[&lambda.id]                 // LambdaFacts { escaping, captures: [(binding, Move|Borrow|Mutate)] }
f.temporaries                         // owned values dropped at the end of their statement
f.consumed_scrutinees                 // match/if-let whose payloads own their parts
f.drops_old                           // assignments storing over a binding (drop flag; cleared by a Move)
f.parameters, f.receiver              // inferred ParamMode: Borrow | Mutate (var) | Consume
```

## Model

- **Classes.** `Copy` (scalars, and records/alternatives/tuples of Copy), `Move` (everything else owned), `Resource` (types with cleanup; move-only, never `.copy()`). `Shared[T]` is the only refcounted type and is `Copy`-class sharing. Type variables are `Move` (conservative); handle types are `Copy`-class handles, their `with` resources `Resource`.
- **One owner.** A `Move`-class value passed to a consuming position (consuming parameter, record/list/map element, `return`, `let`/`var` initializer from a non-place, closure capture of an escaping closure) is moved. A move is legal only at the value's last use (backward liveness; loops use a head fixpoint; reassignment kills the old value). Use after move is an error.
- **Modes.** Parameter modes are inferred by a program-wide fixpoint: `Borrow` (read), `Mutate` (declared `var`), `Consume` (moved/stored/returned). `var` is declared in the signature (`var xs: T`, `var fn` receivers) and written at the call (`f(var xs)`); the marker is required exactly where the callee takes `var`. There is no `mut`.
- **Mutability.** `let` is immutable including contents; only `var` bindings, `var` parameters and `var fn` receivers change. Fields/elements of a `var` binding are changed through it.
- **Overlap.** Operands that a call keeps hold of (a `var` argument, a `Move`-class borrow, a closure capture) must not overlap: `f(var a, a)` and `f(var r, r.items)` are rejected. A `Copy` value computed before the call (`f(var xs, xs.length())`) is fine.
- **Borrows are lexical.** Payload bindings, loop variables, `with` bindings, accessor results and `let x = a.b` / `a[i]` / `let y = x` hold a borrow of their origin until the holder's last use (payload and loop borrows last the whole arm/body). While held, the origin cannot be changed, reassigned or moved; closures that mutate a capture hold it exclusively (reads are also rejected). Moving out of a borrow is rejected (`.copy()` first).
- **Mutable borrows.** `var x = a.b` / `a[i]` binds an exclusive borrow of the part: changes through `x` change the origin, which must itself be changeable (`var`). While `x` is live nothing else may read, change, move or borrow the origin (so there is only one mutable borrow at a time; disjoint fields are fine). `x` cannot be reassigned or moved out, and ends at its last use. `let x = a.b` stays a shared borrow. `if var x = a.get(k):` borrows the payload the same way for the branch. A borrow taken through another mutable borrow (`var it = b.items`) may be used while `b` is live, but not the reverse. Lowering names the origin's place instead of copying (`ms-lower/src/alias.rs`), so every exit path writes through; the CLI always runs this pass on functions that hold a mutable borrow. `var x = <call result>` owns.
- **Match / destructuring** consumes an owned last-use scrutinee (payloads own their parts, `consumed_scrutinees`); otherwise payloads are borrows. `var` in a case payload is rejected.
- **Closures.** A closure that is returned, stored or passed to a consuming parameter *escapes*: it owns its captures (moved at creation, so the captured variable is dead afterwards) and may not change them or move them out when called (it can run many times: return `x.copy()`). A non-escaping closure borrows its captures lexically. Escape is inferred per module by fixpoint; native callbacks on collections are non-escaping.
- **Mutators** (`append`, `set`, ...) take their receiver `var` and return `Unit`-like unusable results: chaining and using the result are errors.
- **`.clone()`** is the temporary spelling of `.copy()` (deep value copy); diagnostics say `.clone()` until the rename (`COPY` constant in `walk.rs`).

## Open decisions: resolved here

| Decision | Resolution |
| --- | --- |
| Projections vs copies | Projections (`a.b`, `a[i]`, accessors, payloads) **borrow**; they cannot be moved out of or changed through a `let`; `.copy()` produces an owned value. |
| Mutator results | Unusable (statement position only); no chaining. |
| Closure escape | Escaping closures own captures (move at creation, no mutation/move-out of captures in the body); others borrow. Inferred per module. |
| Generic copyability | Type variables are `Move`; no `Copy` bound. Monomorphization may copy when the instance is `Copy`-class. |
| Handle types | `Copy`-class handles; `with` resources are `Resource` (move-only, no `.copy()`). |

## Rejection corpus

`tests/ownership/reject/*.ms` mark each expected diagnostic with `# error: <substring>`; `tests/ownership/accept/*.ms` must be clean (`cargo test -p ms-check --test ownership`). Index by rule:

| Rule | Programs |
| --- | --- |
| Use after move | `move_then_use`, `move_into_call_then_use`, `move_into_list_literal`, `move_into_record`, `move_in_loop`, `move_in_branch_then_join`, `use_param_after_move`, `moved_value_in_closure_after` |
| Immutability | `mutate_let`, `mutate_field_of_let`, `mutate_param`, `assign_field_of_borrow` |
| `var` markers | `missing_var_marker`, `extra_var_marker`, `var_argument_of_let`, `var_argument_not_a_place`, `receiver_without_var_fn`, `receiver_var_method_from_plain_method` |
| Overlap | `overlapping_var_arguments`, `holder_passed_with_var_root` |
| Borrow exclusivity | `borrow_held_across_mutation`, `borrow_held_across_loop`, `borrow_held_across_branch`, `loop_mutates_iterable`, `match_payload_reassign`, `reborrow_chain` |
| Move out of borrow/var | `consume_borrowed_binding`, `projection_move_out`, `match_payload_move_out`, `loop_variable_moved_out`, `return_borrowed_binding`, `var_parameter_moved_out` |
| Closures | `closure_exclusive_borrow`, `closure_borrow_then_mutation`, `closure_reads_changed_variable`, `escaping_closure_changes_capture`, `escaping_closure_takes_capture` |
| Mutable borrows | `var_borrow_second_mutable`, `var_borrow_read_origin`, `var_borrow_mutate_origin`, `var_borrow_of_let`, `var_borrow_reassigned`, `var_borrow_moved_out`, `if_var_of_let`, `if_var_read_origin`, `if_var_mutate_origin`, `if_var_reassigned` |
| Mutators | `mutator_chaining`, `mutator_result_used` |

## Behavior changes for the migration tool

Programs written for reference semantics change as follows:

1. **Aliasing is gone.** `let b = a` of a `Move`-class value borrows (if `a` stays used, `b` is a read-only view that blocks changes to `a`) or moves (last use). Code relying on two names changing one object must pass `var` explicitly or restructure.
2. **`.clone()` is deep** and renamed `.copy()`; `.clone()` for a cheap shallow share becomes a borrow or a `Shared[T]`.
3. **Mutator chaining/results** (`xs.append(1).append(2)`, `values.prepend(0).set(1, 9)`) become separate statements; results of mutators are not values.
4. **Implicit parameter mutation.** A function that changes a parameter declares it `var` and every caller writes `var` at the argument.
5. **`let` is deeply immutable.** `let xs = []; xs.append(1)` becomes `var xs`.
6. **Closure capture is by borrow or move,** not by snapshot of a shared reference; a closure that mutates its capture exclusively borrows it, an escaping one owns it.
7. **Iteration while mutating** the iterable (`for v in xs: xs.fill(..)`) is rejected.
8. **Accessor-then-mutate** (`let first = xs[0]; xs.append(..); use(first)`) is rejected; `.copy()` the part or finish using it first.
9. **Field assignment through calls/borrows** (`receiver(log, v).val = ...`, `let alias = rec; alias.f = 1`) is rejected; assign through the owning `var`.

## Limits

- Indexed assignment `xs[i] = v` has no syntax yet (`set` is the mutator).
- `var` parameters, `var` call arguments and `var fn` are syntax additions (`ms-syntax`: `Param.mutable`, `Argument.mutable`, `Method.mutating`).
- Native modes come from `collection_mutation` plus type-shape heuristics; a native that consumes an argument without a collection signature is treated as `Borrow`.
- Moved-on-every-path is not tracked forward: `drops_old` is a may-drop fact paired with a drop flag cleared at `Move` uses.
- Impl-vs-interface mode agreement is not checked yet.
