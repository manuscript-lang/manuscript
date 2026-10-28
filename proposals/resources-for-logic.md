# Resources for logic

## Summary

- Problem: the policies a human wants enforced on agent-written code (money is conserved, destructive actions need an approval, authenticate before query, secrets never reach logs, untrusted input never reaches SQL, only these hosts) live in prose and review. The compiler enforces none of them, and tests only sample them.
- Change: let programs declare their own **resources** and reuse the ownership checker that already enforces memory and host resources. Two general primitives: a standard `Linear` interface the checker recognizes (a value is consumed exactly once, never copied, never dropped) and sealed constructors (only the declaring module creates the value). Typestate, witnesses and labels then need no new mechanism: each is verified against current `ms check` below.
- Cost: one checker rule family for `Linear`, one amendment to the private-field-types rule, a stdlib kit in `.ms` (`Money`-style quantities, `Approved[T]`, `Secret[T]`, `Untrusted[T]`), later an opt-in `[permissions]` manifest table. No new syntax, no keyword, no prover, no solver.
- Decision requested: approve stages 1 and 2. Stages 3 and 4 (capabilities as values, `ms review` policy) reuse the capabilities proposals and are approved separately.

## Status

- Proposal, 2026-10-28, checked against main `5664578e`. Every `.ms` example below ran under `ms check` from that build; proposed behavior is marked "proposed" and its diagnostic text is expected, not pasted.
- Direction (Chinmay, 2026-10-28): "think of a bullet proof way to write programs, we have worked our way with memory and resources, now it's time to tackle to logic constraints"; "this feels like jsonschema ported to types, how can we specify higher level objectives"; "these feel like tests, how are they different"; "think from the perspective what policies humans would want to enforce on a program that will be enforced while agents write the code"; "think from first principles not just another variation of tests and json schema"; "consolidate everything under one line of thought"; "accommodate and create new proposal, follow the repo skills".
- Supersedes `contracts-effects-refinements.md` (same branch, withdrawn): `requires`/`ensures`/`where` and `uses` annotations are dropped, see Alternatives. Builds on the project-file proposals `capabilities-enforcement.md` and `capabilities-os-mechanisms.md` (authority manifest, OS layer) and the `policy-end-to-end.md` draft (its ledger is the worked example here, without a rule language). Survey of other systems: project file `logic-enforcement-research.md`.
- Kept decisions: parameterless `main`, imported host accessors by default, ordinary service parameters, no per-function authority annotations. Stage 3 changes accessor rules only for projects that opt in with a manifest table, which the earlier "defer enforcement" decision (`.experts/language.md`, "Parameterless main and imported host accessors") allows once this is approved; that entry and the `language-design-taste` line are updated in the stage 3 PR.
- Skeptical review: requested in a separate thread; outcome to be recorded here.

## Problem

The compiler already refuses to lose or duplicate a value with one owner:

```manuscript
type Money:
    note: String

def keep(m: Money) -> Money: m

export def main() -> Int:
    let m = Money(note: "five")
    let a = keep(m)
    let b = keep(m)
    return a.note.length() + b.note.length()
```

```text
keep.ms:8:18: type: `m` is moved here but used again at 9:18; a value has one owner, so pass `m.clone()` to keep the original, or move it only at its last use
```

It also refuses an unread binding (`local binding m is never read`, `crates/ms-check/src/unused.rs:113`) and a discarded `Result` (`this statement discards Result[Int, Error], so a failure would be lost`, `crates/ms-check/src/stmts.rs:358`). But the same `Money` with an `Int` field copies implicitly, `.clone()` is always available, a value that was read can be dropped at scope end, and any module can construct `Money(cents: 1)`. So a program can mint money, spend it twice, or forget a refund, and the checker is silent. The same holds for an approval token, a session state, a validated path, or a `Network` handle. Everything a human would call a logic bug in agent code is, structurally, one of: created where it should not be, duplicated, dropped, used in the wrong state, or passed to the wrong sink.

Evidence that the mechanism, not a spec language, is what works is in the research note: Move (linear assets), Austral (capabilities as a consequence of linearity), Obsidian (controlled study, fewer asset bugs than Solidity), and the verified-code-generation benchmarks, where models satisfy fast local checkers and the bottleneck is who writes and validates the spec.

Non-goals: proving arithmetic facts (index in range, sorted output) stays with faults, witness types and tests; a prover or SMT backend; changing `main`; OS sandboxing (capabilities proposal, Layer 3); effect annotations.

## Design

One rule: **a type may declare itself a resource; the checker then applies to it the discipline it applies to memory and host handles.** Humans write the resource types; agents write the functions; `ms check` is the reviewer.

### Linear types

`Linear` is an empty standard interface in `@std/core.ms`, recognized by identity like `Closeable` (`documentation/core-language/cleanup/closeable.md`). `impl Linear for T:` makes `T` linear. In this proposal the stub has one placeholder operation because an empty interface does not parse today; the stdlib version is empty, which needs the parser to accept an empty interface body (one small change, listed in Components).

Rules for a linear value (proposed):

- It is never copied: no implicit copy even when all fields are scalars, and `Clonable` cannot be implemented. Passing it as an argument always moves it; the callee owns it and must consume it.
- It is never dropped: every control-flow path must move it into a consuming position (a parameter, a field, a return, a collection). Scope end, reassignment of a `var` holding it, `let _ = ...`, and an unread binding are errors. `try` and early `return` paths count.
- Faults and cancellation abort and release the value through the existing fault-site drop; they are not drops the rule reports.
- Its constructor is sealed (below), so only the declaring module creates it; a module that creates it also declares how it is destroyed (a consuming function such as `deposit` or `burn`).
- A record with a linear field is linear. A `List`, `Map`, `Optional` or `Result` whose element type is linear is linear; standard methods that drop an element (`clear`, `remove` returning `Unit`, `xs[i] = v`) are unavailable on it (stage 2, tagged in `bindings.json`).
- A closure that captures a linear value owns it and is itself linear (must be called exactly once); stage 1 rejects escaping capture and allows non-escaping borrow.
- An interface operation may take or return linear values; implementations follow the usual signature rules. `Linear` and `Closeable` are exclusive: a closeable value is released by `close` at scope end, which is a drop.
- A generic body may drop `T` only if `T` has no `Linear` bound; instantiating such a `T` with a linear type is an error at the instantiation. Stdlib containers are audited in stage 2 instead.

Diagnostics follow the existing shapes and name the fix:

```text
# proposed
ledger.ms:40:9: type: `m: Money` is not consumed on every path; Money is linear, so move it into `deposit`, return it, or store it (a linear value cannot be dropped, copied or cloned)
ledger.ms:12:30: type: Money(cents: 5) cannot be built here; Money is sealed to module ledger.ms, call `mint` or another exported constructor
```

### Sealed constructors

Today an exported record exports its constructor, and a field of a private type is rejected (`public signature exposes private type Seal`). The private-field-types proposal (project files, owner direction 2026-10-26) relaxes the closure rule for record fields and requires hidden fields to have defaults so outside constructors can omit them. One amendment seals a constructor: **a hidden field without a default makes the constructor usable only in the declaring module.** No syntax; a module seals a type by adding one private field.

```manuscript
# proposed: checks once private-field-types lands with the amendment
type Seal:

export type Secret[T]:
    value: T
    seal: Seal

export def secret[T](value: T) -> Secret[T]: Secret[T](value: value, seal: Seal())
```

Linear types are sealed implicitly (a linear type with a public constructor defeats its own purpose); the private field is not required for them.

### What already works: typestate, witnesses, labels

These need no change. Each example below is current `ms check` output.

Order of operations through phantom parameters and per-state interfaces:

```manuscript
type Open:
type Authed:

type Connection[S]:
    host: String

interface Querying:
    def query(sql: String) -> String

impl Querying for Connection[Authed]:
    def query(sql: String) -> String:
        return f"{self.host}: {sql}"

export def main() -> Int:
    let a = Connection[Authed](host: "db")
    let c = Connection[Open](host: "db")
    let r = a.query("select 1")
    let bad = c.query("select 2")
    return r.length() + bad.length()
```

```text
iface.ms:18:17: resolution: unknown or ambiguous member query on Connection[Open]; available: host
```

A transition is a consuming function `def authenticate(conn: Connection[Open], token: String) -> Connection[Authed]`; calling `query(c, ...)` on the `Open` value fails with `expected Connection[Authed], found Connection[Open] (in argument 'conn' of query)` (verified). With `Linear` on `Connection`, the `Open` value cannot also be kept and reused after the transition.

A label is a wrapper whose sinks take the plain type:

```manuscript
type Secret:
    value: String

def log_line(line: String) -> Int: line.length()

export def main() -> Int:
    let key = Secret(value: "k-123")
    return log_line(key)
```

```text
secret.ms:8:21: type: expected String, found Secret (in argument 'line' of log_line)
```

Sealing makes `Secret` and `Untrusted` meaningful across modules: only `secret()` builds one and only `declassify` opens it; only an input boundary builds `Untrusted[String]` and only a validator turns it into `Sql`, `UserId` or `SafePath`. The typestate diagnostic in stage 1 is extended to name the transition ("call `authenticate` first") when the receiver type has an implementation of the operation at another type argument.

### Worked example: the ledger

Human-owned types (`ledger.ms`), verified with the `Linear` stub:

```manuscript
interface Linear:
    def linear() -> Unit        # stub; empty in @std/core.ms

export type Money:
    cents: Int

impl Linear for Money:
    def linear() -> Unit: ()    # stub line

export def mint(cents: Int) -> Money: Money(cents: cents)

export def split(m: Money, cents: Int) -> List[Money]:
    return [Money(cents: cents), Money(cents: m.cents - cents)]

export def merge(a: Money, b: Money) -> Money: Money(cents: a.cents + b.cents)

type Account:
    id: String
    balance: Money

type LedgerError:
    case Insufficient

impl Error for LedgerError:
    def message() -> String: "insufficient funds"

impl Account:
    var def withdraw(cents: Int) -> Result[Money, LedgerError]:
        if cents > self.balance.cents: return error(Insufficient)
        self.balance = Money(cents: self.balance.cents - cents)
        return ok(Money(cents: cents))

    var def deposit(m: Money) -> Unit:
        self.balance = Money(cents: self.balance.cents + m.cents)
```

Agent-written function:

```manuscript
def transfer(var from: Account, var to: Account, cents: Int) -> Result[Unit, LedgerError]:
    let m = try from.withdraw(cents)
    to.deposit(m)
    return ok(())
```

With the rules above: deleting `to.deposit(m)` is "`m: Money` is not consumed"; depositing twice is the existing "moved here but used again"; writing `Money(cents: 100)` in another module is "sealed to module ledger.ms". Conservation holds for every program that compiles, with no invariant, rule evaluator or fuzzer. (Stage 1 ergonomics note: `withdraw` and `deposit` above rebuild the field; stage 1 also accepts moving a linear field out of a `var self` and back.)

### Worked example: a web service

Verified today except sealing (single module); the proposed stdlib types are stubbed:

```manuscript
type Untrusted[T]:
    value: T

type Authed:
type Anonymous:

type Session[S]:
    user: String

type Approved[T]:
    token: String

type Delete:

type UserId:
    value: String

type Secret:
    value: String

type AppError:
    case BadId
    case Forbidden

impl Error for AppError:
    def message() -> String: "request rejected"

# The only way to get a UserId from request text.
def parse_user_id(raw: Untrusted[String]) -> Result[UserId, AppError]:
    if raw.value.length() == 0: return error(BadId)
    return ok(UserId(value: raw.value.clone()))

def login(session: Session[Anonymous], token: Secret) -> Result[Session[Authed], AppError]:
    if token.value != "ok": return error(Forbidden)
    return ok(Session[Authed](user: session.user.clone()))

# Only an authenticated session can read a profile.
def profile(session: Session[Authed], id: UserId) -> String:
    return f"{session.user} viewed {id.value}"

# Deleting consumes one approval; a second delete needs a second approval.
def delete_account(session: Session[Authed], id: UserId, approval: Approved[Delete]) -> String:
    return f"{session.user} deleted {id.value} with {approval.token}"

def handle(path: Untrusted[String], token: Secret) -> Result[String, AppError]:
    let anonymous = Session[Anonymous](user: "guest")
    let id = try parse_user_id(path)
    let session = try login(anonymous, token)
    return ok(profile(session, id))

def handle_wrong(path: Untrusted[String]) -> Result[String, AppError]:
    let anonymous = Session[Anonymous](user: "guest")
    let id = try parse_user_id(path)
    return ok(profile(anonymous, id))
```

```text
web.ms:54:23: type: expected Session[Authed], found Session[Anonymous] (in argument 'session' of profile)
```

Policies this encodes, each enforced by the type checker: route text is `Untrusted` until a validator accepts it; a profile needs an authenticated session; an account deletion needs an `Approved[Delete]`, and once `Approved` is linear each approval serves one deletion (today `delete_account(id, approval)` twice is accepted because the callee only reads it; under the linear rule the second call is "moved here but used again"). In the stdlib, `HttpExchange.path()` and `query()` return `Untrusted[String]` under an opt-in, and the router passes a `Session[Anonymous]` into every handler; the gate that mints `Approved[Delete]` lives in a human-owned module.

### Worked example: a command-line tool

Verified today:

```manuscript
from "@std/fs.ms" import FileSystem, FileSystemError

type Untrusted[T]:
    value: T

type Confirmed:
    note: String

type SafePath:
    path: String

type CleanError:
    case Outside

impl Error for CleanError:
    def message() -> String: "path outside the working root"

# The only way to turn user text into a path the tool may touch.
def inside(root: String, raw: Untrusted[String]) -> Result[SafePath, CleanError]:
    if raw.value.contains(".."): return error(Outside)
    return ok(SafePath(path: f"{root}/{raw.value}"))

# Removal needs the filesystem it was handed, a checked path, and one confirmation.
def remove(fs: FileSystem, target: SafePath, go: Confirmed) -> Result[Unit, FileSystemError]:
    return fs.remove(target.path.clone(), recursive: False)

def run(fs: FileSystem, root: String, args: List[Untrusted[String]], go: Confirmed) -> Result[Int, Error]:
    let first = try inside(root, args.get(0, default: Untrusted[String](value: "")))
    try remove(fs, first, go)
    let second = try inside(root, args.get(1, default: Untrusted[String](value: "")))
    try remove(fs, second, go)
    return ok(0)
```

Policies: arguments are `Untrusted` until `inside` accepts them, so `..` never reaches `fs.remove`; the tool only touches the `FileSystem` it was handed (stage 3 narrows it with `FileSystem.restrict(read:, write:)` to `root` before `run` is called, and rejects `filesystem()` inside `run` under `[permissions]`); with `Confirmed` linear, the second `remove(fs, second, go)` is an error, so a `--force` confirmation covers exactly one destructive action and a batch needs one per item, or a `Confirmed[Batch]` minted by the prompt.

### Capabilities as values (stage 3)

Under a `[permissions]` table in `ms.toml` (the parser accepts only `[project]` and `[aliases]` today, `crates/ms-driver/src/project/manifest.rs:1`), ambient accessors (`network()`, `filesystem()`, `commands()`, `control()`, `system()`, `terminal()`) are accepted only in the entry module; everything else receives capabilities as parameters and narrows them with `restrict`. `Network.restrict` exists (`stdlib/net.ms:268-303`); `FileSystem.restrict` and `Commands.restrict` are added per the capabilities proposal. Effects stay inferred from the capabilities a function receives (`crates/ms-check/src/effects.rs`) for `ms review` and `ms diagram`; no `uses` annotation.

### Policy diff (stage 4)

`ms review` reads `policy/` (frozen exported signatures, dependency set, modules only humans may edit) and fails a review that changes them. This is a diff over facts `ms inspect` already emits; it is the one part of the design that is not a type and is covered by the capabilities proposal's `ms review` authority diff.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-syntax` | accept an empty `interface` body (for `Linear`); otherwise unchanged, no new tokens | parser accept fixture |
| `crates/ms-check` ownership (`ownership/mod.rs`, `modes.rs`, `walk.rs`) | linear class: no copy, always-move arguments, must-consume on every path, drop sites reported | `tests/e2e/testdata/reject` cases: drop at scope end, `let _`, reassignment, early return, `try` path, escaping closure, clone |
| `crates/ms-check` contracts (`contracts.rs` `fn public`) | sealed constructor amendment to private-field-types; linear types sealed implicitly | reject: construct outside module; accept: via exported constructor |
| `crates/ms-check` diagnostics | the two messages above; typestate hint naming the transition | conformance `check` fixtures with exact text |
| `crates/ms-lower`, `ms-mir`, codegen, `ms-rt`, ABI | unchanged: a linear value lowers like any owned value | existing e2e |
| `stdlib/core.ms` | `interface Linear:` | prelude fixture |
| `stdlib/bindings.json` | stage 2: `drops_element` tag on collection methods | audit test |
| `stdlib/resources.ms` (new, `.ms` only) | `Approved[T]`, `Secret[T]`, `Untrusted[T]`, `Confirmed`, quantity pattern (`split`, `merge`) and documented typestate pattern | `ms test` fixtures |
| `stdlib/http.ms`, `cli.ms` | stage 2 opt-in: `Untrusted[String]` for request path, query, header values, CLI arguments | fixtures |
| `stdlib/fs.ms`, `process.ms` | stage 3: `restrict` on `FileSystem`, `Commands` | fixtures per capabilities proposal |
| manifest (`ms-driver`) | stage 3: `[permissions]` | manifest tests |
| formatter, lint | unchanged (no syntax); lint hint for a linear value passed where a borrow would do | lint tests |
| LSP, VS Code | hover shows "linear" and "sealed"; diagnostics as above | LSP tests |
| CLI | stage 4: `ms review` policy diff | CLI tests |
| documentation | `types/resources.md` (linear, sealed, typestate, labels), update `types/records.md` construction rules, `glossary.md` "resource"; `.experts/language.md` entry in stage 3 | `make docs`, repo-check |
| platform parity | compiler and `.ms` only; nothing OS-specific | CI matrix, nothing gated |

## Alternatives

- Do nothing: policies stay in prose; the agent-error classes above stay runtime or review findings. Baseline the agent-bench arm in Staging must beat.
- Contracts and refinements (`requires`/`ensures`/`where`, the withdrawn proposal): describe a value's shape at one point and need a prover for anything non-trivial; the skeptical review found no proof-rate evidence. A witness type carries the same fact with no prover, so they are dropped. Arithmetic facts remain a possible later stage behind witness types.
- Effect annotations (`uses net.connect`): redundant once a capability is a parameter; Wyvern and Scala 3 derive effects from capabilities. Dropped.
- Property tests and a policy rule language (`action`/`policy`): tests sample runs and a rule evaluator checks at runtime; both are extensional and neither compose. The ledger needed pre/post snapshots and a fuzzer to approximate what linearity gives by construction. Tests stay tests.
- A `linear` keyword instead of the `Linear` interface: one token, same semantics; rejected because `Closeable` already sets the precedent of a compiler-recognized standard interface and the skill prefers no syntax.
- Field visibility modifiers for sealing: more syntax for one rule; the hidden-field amendment composes with the already-requested private-field-types change.
- Smallest version: stage 1 alone (linear plus sealed) already makes `Money`, `Approved` and `Confirmed` enforceable with no stdlib kit.
- Drawbacks: every path must consume a linear value, including error branches, which the `Result` must-use rule already imposes and users accept; linear values in stdlib collections wait for stage 2; closures capturing linear values are restricted in stage 1. Comparable languages: Move and Austral restrict in the same places and ship.

## Staging and verification

1. **Linear and sealed.** `Linear` in `@std/core.ms`, ownership rules, sealed constructors, diagnostics, docs page. Gate: reject fixtures for every drop site listed above; the full conformance corpus and every existing program unchanged (no type implements `Linear` yet); `cargo nextest`, `make verify`.
2. **Resource kit and containers.** `stdlib/resources.ms`; `drops_element` audit of `List`, `Map`, `Set`, `Optional`, `Deque`, `Queue`; `Untrusted` at the HTTP and CLI boundaries behind an option. Gate: the ledger, web and CLI examples above compile with the stubs removed and fail exactly where marked.
3. **Capabilities as values.** `[permissions]`, accessor rule, `FileSystem.restrict`, `Commands.restrict`; `.experts` and taste-skill updates. Gate: capabilities proposal's own tests; unrestricted projects unchanged.
4. **Policy diff.** `ms review` over `policy/`. Gate: a review that changes a frozen export fails with the surface named.
5. **Evidence.** A `bench/agent/` arm where tasks ship human-owned resource types; compare bug classes and pass rates with the untyped arm and add a dated section to its result page. Go/no-go for further investment (graded resources for budgets, witness types for arithmetic) is that page.

## Open questions

- Linear values captured by escaping closures: reject in stage 1 (recommended) or make the closure linear.
- Whether `Linear` types are also barred from `Shared[T]` (`@std/shared.ms`): yes in stage 1 (recommended), since sharing is copying.
- Whether a linear field may be moved out of `var self` and restored in the same method without rebuilding the record: recommended yes, it is the natural `withdraw` body.
- Accessor rule granularity under `[permissions]`: entry module only (recommended) or any module the table names.
