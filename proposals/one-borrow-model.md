# One borrow model: fold aliasing, borrows and `ref` together

## Summary

- Problem: one idea, "look at memory someone else owns without copying", is built three times. Lexical borrows, exclusive aliasing and `ref` each have their own rules, exceptions and lowering facts.
- Change: a single model with no new syntax.
  - Every binding of a place borrows implicitly: `let` is shared, `var` is exclusive.
  - `ref` appears only on result types and means "every path returns a borrow".
  - The same rule holds for functions, interface operations and function values.
- It deletes the binding markers (`let ref`, `var ref`, `for ref`, `match ref`), `Ownership.lenders`, the `@std/` special case in lowering, and the "a `ref` operation may lend or own" exception.
- Decision requested: approve the rule and stages. A skeptical review (below) shaped this version.

## Status

Approved, 2026-10-25, checked against `7f0a4c39`. Stage 1 (binding markers) and the soundness fixes below landed in #1314; stage 2 (every path lends) is the next PR. `Ownership.lenders` stays as the lowering gate (it now equals the checked `ref` functions) instead of being deleted, so a function the checker did not vet never gets a lent instance. An adversarial review after stage 2 found four use-after-free paths dating from #1299 (a lowering copy of a `match` scrutinee, a loop iterable or a `let` was lent, and a default argument counted as a place); the fix PR closes them and adds the MIR verifier check that a lent `ret` never derives from a value the function owns. Stage 3 keeps `getters` keyed by call node: replacing it with the callee's exported `plain` would move the same lookup without deleting code. Decisions from the user (project thread):

- "reference is basically a handle for an object someone else owns, following the same multiple immutable one mutable pattern"
- "where moving is easier we should follow that, reference is looking into memory someone else holds without copying" (so `Error.message` becomes owning)
- "i think we've built three things with similar meaning aliasing borrows and ref, can we combine them"
- "yes doing that implicit is fine": an unmarked `let x = a.b` keeps borrowing.
- "var ref on return is unnecessary, we should just do ref, and let mutability at the caller with let and var binding"
- "returning a ref from arguments or things that go out of scope/cleaned up after the function ends should be an error"

## Today: three mechanisms (verified)

| | Shared borrows | Exclusive aliasing | `ref` |
| --- | --- | --- | --- |
| Source | `let x = a.b`, `xs[i]`, payloads, loop variables, `with`; no marker | `var x = a.b`, `if var x = m.get(k)`, `var y = f(b)` | `-> ref T` on results (required on lenders); binding markers |
| Checker | origin frozen until last use (`ownership/walk.rs`) | origin exclusive until last use; `Ownership.exclusive`; `Ownership.getters` for the call form, from a read-only slot whose every return is one field path (`walk.rs:357-361`) | `ref_results` (`ownership/mod.rs:244-268`); `Summary.result`; `Ownership.lenders` |
| Lowering | `Mode::Borrow` values; `bind_local` (`func.rs:549-560`) and `bind` (`stmt.rs:229-251`) lend only some shapes by their own tests; `read_borrows` covers pattern and arm bindings only (`mod.rs:364-375`) | path substitution in `ms-lower/src/alias.rs`; a getter call is replaced by its field path and never called (`alias.rs:70-82`) | `$lent` instances, `Func.ret_borrowed`, `opt.view`, `Map.get` view; direct calls only, and only for `@std/` or `lenders` (`call.rs:352-364`) |
| Exceptions | lowering copies some checker borrows (above) | getter form needs one field path of the only argument | interface and closure calls copy; a `ref` operation may be implemented by an owner (`mod.rs:297`) |

Binding markers do nothing today:

- `match ref` is parsed and dropped (`ms-syntax/src/parser.rs:2091-2093`). All 11 marker uses in `stdlib/` and `tests/e2e` are `match ref` (`stdlib/json.ms`, `ref-lend-results.ms`).
- `let ref` and `for ref` appear only in `ms-check` tests (`accept/ref_result.ms`, `accept/ref_loop_and_match.ms`). Their only effect is an extra rejection on an owned value (`walk.rs:970`, `walk.rs:1032`).
- The conformance tag `aliasing` is unrelated. It marks old shared-mutation programs that value semantics rejects.

## Design

**A borrow is a handle to a place another binding owns: many readers or one writer, ending at its last use and never outliving the owner.**

Bindings:

- `let x = place` is a shared borrow. `var x = place` is an exclusive borrow. A binding of a call or literal owns, as today.
- `var y = f(b)` where `f` returns `ref` is an exclusive borrow of the call's borrowable arguments. This is today's behaviour, stated as one rule, not a getter special case.
- Lowering limit (not a language rule): an exclusive borrow lowers as a place path, so `f` must return one field path of its argument. Other `ref` calls bound with `var` keep today's diagnostic (`reject/ref_result_two_paths_var.ms`).

Results:

- `-> ref T` means every path returns part of a parameter or the receiver (or `none` / `some(part)` for `ref Optional[T]`). A path that returns an owned value is a diagnostic. This merges today's two checks (marker required on lenders; at least one lending path) into one, and makes every `ref` function a lender.
- A function without `ref` owns its result. A part of a parameter returned without `ref` stays rejected (fix: `ref`, or `.clone()`).
- Lowering: every `ref` function gets the lent instance. `Ownership.lenders` and the `@std/` test in `call.rs` are deleted.

Interface operations and function values (same rule):

- A `ref` operation is implemented only by a `ref` function or a native declared `ref`. Vtable thunks call the lent instance; `CallMethod` yields a borrow.
- `Error.message` becomes owning.
- `Callable[[T], ref R]`: a lambda or function value of that type lends from its **parameters only**. An escaping closure owns its captures, so a borrow of a capture could outlive the call.
- `and_then` with a `ref` callback returns a borrow of its receiver, so the receiver must be a borrowed place, not an owned temporary. `map` wraps its result in a new value and cannot lend.

Checker facts for lowering:

- `exclusive` and `read_borrows` become one `HashMap<usize, Kind>` from `BindingFacts`, covering every binding kind, not only patterns. The `bind_local`/`bind` shape tests then read the fact.
- `getters` (keyed by call node) becomes the callee's exported `Summary.result.plain`; `alias.rs:71` already resolves the callee.
- `lenders` disappears: a lender is a `result_ref` function.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-syntax` | delete `by_ref` (`ast.rs:648,699`) and the marker branches (`parser.rs:1227-1245,1404-1418,2093`); later `ref` in `Callable` results | parser tests, formatter round trip |
| `ms-check` ownership | delete marker rejections; one "every path lends" check; one binding-kind map; export `plain`; lender rule for interface operations | `tests/ownership` (two marker reject cases removed; `ref_impl_owns_under_ref` becomes reject) |
| `ms-lower` | read the binding-kind map in `bind_local`/`bind`; lent instance for every `ref` function; thunks; closure lent instances | `ref-lend-results.ms`, getter fixtures |
| `ms-mir` | `MethodSig.ret_borrowed`; indirect-call result mode (stage 4) | verifier tests |
| `stdlib/*.ms` | drop `match ref` in `json.ms`; `Error.message` owning; `ref` callbacks for `and_then` | `json-accessors.ms` |
| Docs | `references.md` and `OWNERSHIP.md` state one model; drop marker text (`references.md:15`, `loops.md:78`) | `make docs-check` |

## Alternatives

- Do nothing: three rule sets with their own exceptions stay.
- New `-> var ref T` result syntax for exclusive getters: rejected in review. It deletes no inference (lowering still needs one static field path), cannot lower through interface dispatch, and adds a diagnostic.
- Require `ref` markers on bindings: rejected by the user ("implicit is fine").
- Pointer-based exclusive borrows (delete `alias.rs`): needs new MIR store operations; path substitution already works on every exit path.

## Soundness invariants

An independent soundness review probed today's lending with valgrind and a counting runtime (no leak or double free in any probe). It found two holes, both fixed in the first PR:

- **Temporary argument (use-after-free).** `return either(s, make(), flag)` counted only `s` as an origin (`call_origins` skips non-places), so the function lent a borrow of the temporary dropped at `return`. Now a lending call whose lent argument is a temporary, directly or through a projection or another lending call, is an owned path (`lends_owned` in `walk.rs`).
- **`try` exit.** A `try` in a `ref` function returns the owned failure; the checker now counts it as an owned path, so lowering no longer reports a `ref` violation for a checked program.

Invariants every later stage keeps:

- A result is lent only when every path returns part of a parameter that outlives the call; a temporary or `try` exit makes the path owned (stage 2 turns this from a copy into a diagnostic).
- The binding-kind fact (stage 3) says "owned" when the origin is a temporary; lowering never trusts a borrow fact over a temporary.
- A borrow through an interface value created by implicit conversion borrows the converted temporary, so it follows the temporary rule (stage 4); runtime-handle (`natiface.rs`) `ref` operations are rejected.
- A `ref` callable lends only from its parameters, and assigning it to a plain callable type wraps it in a copying thunk; natives and generic instances compiled for owned results never see a borrow (stage 5).
- `and_then` with a `ref` callback needs a receiver whose origins are places, transitively, with no temporary (stage 5).
- Stage 2 adds a MIR verifier check that a lent `ret` value derives from a parameter.

## Staging and verification

Each stage lands green on its own (`cargo test --workspace`, `make conform`, clippy, fmt).

1. Delete binding markers. No behaviour change except two removed rejections; formatter and docs updated.
2. Every path of a `ref` function lends. Delete `lenders` and the `@std/` special case. Add reject cases for an owning path in a `ref` function and an e2e case for `return f(x)` where `f` takes an interface parameter, since an interface conversion makes a temporary copy.
3. One binding-kind fact, plus `plain` exported per callable instead of `getters`. Lowering reads facts, not shapes.
4. Interface operations follow the rule. `Error.message` becomes owning.
5. `ref` in function types and `and_then`, then drop the `.clone()` note in `json.ms`. Gate: `json.navigate` does not regress.

## Open questions

- Stage 5, `and_then`: one declaration whose result is a borrow when the argument lends and owned otherwise (decided per call site, since `and_then` lowers inline), or two names. Recommend one declaration.
