# Object types: say what a shared thing is, delete `Shared` and `lock`

## Summary

- Direction (Chinmay, 2026-10-30): "there should be no channel as the base, we should encode objects for what they are"; "figure out how to get rid of shared".
- Every `Shared[X]` in the library wraps a type that already says what it is: `Lane`, the task result, the registries, `Inbox`, the logger transport, router test state. The box adds nothing but aliasing, and `lock` adds a guard only because a box's payload must move out to be edited.
- Proposed: a type is declared as an **object** when its identity matters. Copies of an object refer to the same instance; methods change it in place; it is freed with its last holder. A plain `type` stays a value. No `Shared`, no `lock`, no guard, no payload move.
- This is what the compiler already does for builders: `ListBuilder` is a refcounted cell holding a record, mutated in place through its address (`crates/ms-lower/src/sharedbuilder.rs`). Object types generalize that from five hand-lowered builders to any declared type.
- Deletes: `shared.ms`, `sync.ms`, `SharedGuard`, `Ticket`, `take/put/locked/id`, the three #1422 special cases (`guard_held`/`copy_if`, `close.rs` guard skip, `constfaults.rs` relock rule), `check_shared_use`, and the lock choreography in five stdlib modules.
- Decision requested: the declaration form (open question 1). It is a language change.

## Status

Proposal, 2026-10-30, against `origin/main` at `69d78f65`. Supersedes every earlier proposal on this branch (`shared-guard-consuming-close.md`, `retire-shared.md`, `owner-task-state.md`, `mutex-guard-naming.md`, `lock-api.md`, `channels-as-base.md`). Their reviews established: guards are held across waits in the library, native per-purpose objects cost 600-900 Rust lines, a channel base breaks logger and router contracts. This design needs no new runtime object and no Rust per use. Nothing implemented.

**Skeptic review (2026-10-30): do not build as written.**
- The builder path is not in-place: `builder_call` takes, mutates and puts back (`sharedbuilder.rs:154-157`), and user `var fn` calls are copy-in/copy-out (`ir.rs:121-123`). An object field call would leave stale bits during the call, the #1422 bug moved to every object. A by-address `var` mode across MIR, interpreter, passes and clif is required.
- Borrow safety needs every wait, closure and interface call treated as a possible write, which rejects stdlib loops (`workers.ms:245-251`, `processes.ms:454-458`, `router.ms:435`). Today's `get` rules and in-use fault are stricter.
- Sites that hold a lock across a wait (`Worker.wait`, log `send`/`flush`/`close`, group closes) rebuild a lock by hand with flags, wait lists and a cancel ticket. Users lose exclusion across waits entirely.
- Many `Shared` sites wrap anonymous types (`Map`, `List`, `Int`, an interface) and need new declarations; cycles leak and skip close; a close from drop glue that waits switches tasks at invisible points; `.clone()`, hashing and derivations are undefined.
- Size is several thousand Rust lines, against about 40 lines of special cases removable by fixing the guard in place (payload `Optional`, or a compiler-known guard moved out on close).

## Problem

- Verified: `Lane[T]` (`tasks.ms:111`) is an ordinary record with `var fn pop`, `clear`, `wake`. It is wrapped as `Shared[Lane[T]]` only so sender and receiver see one instance; every use is `var g = lock(lane); g.value.pop(); g.close()`.
- Verified: the same holds for `Shared[List[T]]` result slots, `Shared[Map[Int, Entry]]` registries, `Inbox`, `Shared[Transport]` and router `TestState`.
- Verified: the guard exists because editing a box's payload needs the payload as a `var`, so `lock` moves it out and `close` moves it back; the stale copy is what #1422 special-cases.
- Verified: tasks switch only at waits, so a method that does not wait cannot be interleaved; mutual exclusion is only needed where a method waits mid-update.
- Non-goals: cross-thread sharing (objects are rejected in worker and process messages, as `Shared` is today); changing builders or native handles.

## Design

```manuscript
object Lane[T]:
    front: List[T] = []
    back: List[T] = []
    sender_closed: Bool = false
    receiver_closed: Bool = false
    waiting: List[Int] = []

# before
var lane = lock(self.outgoing)
lane.value.back.append(value)
lane.value.wake()
lane.close()

# after
self.outgoing.back.append(value)
self.outgoing.wake()
```

- **Identity.** Constructing an object allocates one refcounted cell. Copying the binding, passing it, or storing it in a field adds a holder; the last holder drops the fields. Equality is identity (`==` compares instances).
- **In place.** Field reads and writes and `var fn` calls on an object go through its address, in any binding, including `let` bindings and fields of non-`var` receivers. `let` fixes which object, not its contents.
- **Borrow safety.** A `ref` view of an object's field (`for x in obj.items`, a `ref` result) must not outlive a write to that object. Rule: inside a borrow of an object's field, a call that may write the same object type is rejected, and a runtime "object is borrowed" fault covers what the checker cannot see (the role `get` while locked plays today).
- **Waits.** A method that waits mid-update says so with data, not a lock: the logger keeps `writing: Bool` and a wait list in its transport object; worker and process joins keep their outcome and joined flag in the object. This replaces the four lock-across-wait sites in the skeptic findings.
- **Closeable.** An object implementing `Closeable` is closed by its last holder, as a `Shared` of a `Closeable` is today; it is not move-only, since sharing is the point.
- **Messages.** An object, or a value containing one, is rejected as a worker or process message.
- **Users.** User code that wanted `Shared` + `lock` declares an object. `Counter` in `references.md` becomes `object Counter: count: Int = 0` and `counter.count += 1`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-syntax` | object declaration | parser tests, formatter |
| `crates/ms-check` | object type kind; identity copy; message rejection; borrow rule; delete `check_shared_use`, relock rule | reject corpus |
| `crates/ms-lower` | object construction and field access through `SharedNew`/`SharedAddr`, as builders do; builders become std objects, shrinking `sharedbuilder.rs` | e2e, leak check |
| `crates/ms-clif` | delete `guard_held`, `copy_if` | `cargo nextest run --workspace` |
| `stdlib/tasks.ms`, `workers.ms`, `processes.ms`, `log.ms`, `router.ms` | `Shared[X]` fields become object fields; locks deleted | existing fixtures |
| `stdlib/shared.ms`, `sync.ms` | deleted | |
| docs, tests | `references.md`, `scopes.md` and others; about 66 test files move to objects | `make docs`, `make conform` |

## Alternatives

- **Keep `Shared`, fix the guard (#1422).** Smallest; keeps a box whose only job is aliasing and a guard whose only job is undoing the box.
- **Channels or owner tasks as the base.** Rejected by review and by Chinmay.
- **Per-purpose native objects.** 600-900 Rust lines, against Manuscript first.
- **Do nothing.** Special cases and `lock` footguns stay.

## Staging and verification

1. Spike locally: object declaration, lowering via the builder path, `Lane` converted. Gate: `tasks` fixtures pass, 0 leaks, channel throughput not worse. Go/no-go here.
2. Remaining stdlib sites, including the wait sites with explicit flags.
3. Delete `Shared`, `lock`, the guard and special cases; migrate tests and docs; `make verify-full`.

## Open questions

- Declaration form: `object Lane[T]:` (recommended: one plain word; "values are copied, objects are shared"), or `type Lane[T] is object`?
- Equality by identity, or no `==` at all on objects? Recommendation: identity.
