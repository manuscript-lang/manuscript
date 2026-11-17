# Test mocks and fakes

## Summary

- Problem: a test cannot swap code it did not get as a parameter (clock, files, a helper deep in the call chain) and cannot record calls without a hand-written fake type.
- Change: two parts. `@std/test/mock.ms` (pure Manuscript; built, PR 4372) records calls and queues answers. `fake(original, replacement, body)` swaps any Manuscript function for the length of `body`, in test builds only (prototyped, not pushed).
- Decision requested: approve the scoped `fake` shape and its limits below.

## Status

Implemented in this PR, 2026-11-16, checked against main at 1f593348. Direction (Chinmay): module-level, no capability parameters; tests that fake inner functions are meaningless, so fake only boundaries (2026-11-16, replacing an earlier "any function" pick).

## Problem

```manuscript
fn price(item: String) Int:        // reads a price service in real code
    return lookup(item)

fn total(items: List[String]) Int: // the test only reaches `total`
```

- To test `total` with fixed prices today, `price` needs a parameter, and so does everything between the test and `price`.
- Checking how `price` was called needs a hand-written fake type with its own counter.

## Design

Mocks (built): `Mock0`..`Mock3` by argument count. Answers: `returns_for(args, value)` rules, then `returns_once` queue, then `fallback`; any can be an error. Checks: `calls`, `expect_called_times`, `expect_not_called`, `expect_called_with`, `expect_last_called_with`, `expect_called_matching(check)`, `expect_answers_used`. Features were chosen from Jest, Sinon, Mockito, gomock, mockall and Python mock. Arity is in the name because Manuscript has no variadics or tuples.

Fake (prototype):

```manuscript
test "prices are fixed":
    var lookup = Mock1[String, Int](fallback: 5)
    fake(price, fn item: lookup.call(item), fn:
        expect_equal(total(["a", "b"]), 10)?
        return ok()
    )?
    lookup.expect_called_with("b")?
```

- `fake[F](original: F, replacement: F, body: fn() Void!) Void!`. `original` must be written as a plain function name. Same type `F` means the ordinary checker proves the fit; no new syntax.
- Scoped, not global: the replacement applies while `body` runs, then the original returns. Reason: one owner and borrow-by-default. A replacement that outlives `body` could point at locals that are gone. A scoped one borrows `lookup` safely, so a mock records calls the test can read afterwards. A global `fake(...)` would force the replacement to copy its captures, and the mock's calls would be lost in the copy.
- Allowed: a function written in Manuscript that declares an effect: `@std` boundaries (`now`, `read_file`) or project functions marked `// ms: effect db.write`. Anything else is refused with a message that says to pass the value in as a parameter. Methods that declare an effect are named through an object, `fake(shop.price, fn item: ...)`: Manuscript cannot name a method without one. It replaces that method for every object of the type, and the replacement takes the other arguments, not the object. Also refused: generic functions, functions or methods that change an argument or the object, or return a borrow.
- Why boundaries only: a test that fakes an inner function breaks on refactors and can pass while the real pieces no longer fit. Effects already mark the outside world and tools list them.
- Promises started inside `body` see the fake. Tests in other files running at the same time do not: the table is keyed by the test file's output capture, which promises already inherit.
- Fakes nest, innermost wins. While a replacement runs, calls it makes to the same function reach the original, so a replacement can wrap the real function (Jest's `spyOn`).
- Cost: only functions named by a `fake` call in the test program get a router (a table lookup, then the real body). Every other function is untouched, and `ms run`/`ms build` programs never contain a router.
- Departure from Jest: no global `jest.mock` that stays on, and no automatic restore step to forget. The body is the scope.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-rt/src/fake.rs` | table of (test file, function, closure); push, pop, has, get, clear (about 60 lines) | `e2e/stdlib/fake` |
| `crates/ms-lower` | hand-lowered `fake`; router wrapper for each faked function before ownership elaboration | same |
| `stdlib/test/test.ms` | `export extern fn fake` | docs example |
| `stdlib/internal/test_runner.ms` | clear leftover fakes after each test (a fault inside `body`) | same |
| `stdlib/test/mock.ms` | built | `e2e/stdlib/mock` |

## Alternatives

- Do nothing: parameters and interfaces still work (cookbook). Costs a parameter per caller.
- Global fake until the test ends: closer to Jest, but needs captures copied or a guard type; rejected for the loss of shared mock state.
- Fake any function (the first pick): couples tests to structure; dropped.
- Link-time or file-path swaps: the earlier spike; needs path strings and a second load.

## Open questions

- Name: `fake`, or `replace`/`stub`? Recommendation: `fake`, matching the cookbook page.
- Methods replace for every object of the type. Replacing only one object needs object identity, which the language lacks. Recommendation: keep per-type.
- The refusal messages come from lowering, so they have no source position yet. Recommendation: move the check into `ms-check` before merge.
