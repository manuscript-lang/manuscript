# Resources for logic

## Summary

- Problem: the policies a human wants enforced on agent-written code (an approval is used once, authenticate before query, secrets never reach logs, untrusted input never reaches SQL, money is conserved, only these hosts) live in prose and review. The compiler enforces none of them, and tests only sample them.
- Change: let programs declare their own **resources** and reuse the ownership checker that already enforces memory and host resources. Three rules, no new syntax: **opaque types** (a record with a hidden field can only be built, read, taken apart or structurally converted inside its module), **`Linear`** (a standard interface the checker recognizes: never copied, never dropped, consumed by moving or by taking it apart in its module), and **`State`** (a standard marker for typestate parameters, from which tooling derives the state machine and the "call X first" diagnostic).
- Cost: checker rules for opacity, linearity and typestate hints; a `structural` tag on generic builders in `bindings.json`; a stdlib kit in `.ms`; later an opt-in `[permissions]` table and stdlib handles adopting typestate. No prover, no solver, no keyword.
- Decision requested: approve stage 1 (opaque types, `State`, consume-once tokens, the frozen-module review check, an adversarial corpus and an agent-bench arm). Stage 2 (`Linear` must-consume) is gated on that evidence.

## Status

- Proposal, 2026-10-28, checked against main `5664578e` (review repros on `87d92d70`). Every `.ms` example ran under `ms check`; proposed behavior is marked "proposed" and its diagnostic text is expected, not pasted.
- Direction (Chinmay, 2026-10-28): "think of a bullet proof way to write programs, we have worked our way with memory and resources, now it's time to tackle to logic constraints"; "think from the perspective what policies humans would want to enforce on a program that will be enforced while agents write the code"; "think from first principles not just another variation of tests and json schema"; "consolidate everything under one line of thought"; "accommodate and create new proposal, follow the repo skills"; "type state is interesting, how can we make it a first class idea in stdlib".
- Skeptical review (2026-10-28, project file `architecture/resources-for-logic-review.md`): "direction is sound; stage 1 is under-specified in ways that break the headline claim". Blockers and gaps are resolved in [Review outcome](#review-outcome); stage 1 is rescoped to consume-once tokens as the review suggested.
- Supersedes `contracts-effects-refinements.md` (withdrawn): `requires`/`ensures`/`where` and `uses` annotations are dropped, see Alternatives. Builds on the project-file proposals `capabilities-enforcement.md`, `capabilities-os-mechanisms.md` (authority manifest, OS layer), the `policy-end-to-end.md` draft (its ledger is reworked here), `private-field-types.md` (hidden fields), and the parked `check-use-after-close.md` / `close-is-last-use.md` / `consuming-close.md`, which typestate on `Closeable` resolves generally. Survey of other systems: project file `logic-enforcement-research.md`.
- Kept decisions: parameterless `main`, imported host accessors by default, ordinary service parameters, no per-function authority annotations. Stage 4 changes accessor rules only for projects that opt in; the `.experts/language.md` "Parameterless main and imported host accessors" entry and the `language-design-taste` line are updated in that PR.

## Problem

The checker already refuses to duplicate a value with one owner. A gate module that takes an approval apart gets single use today:

```manuscript
type Delete:

type Approved[T]:
    token: String

def approve(token: String) -> Approved[Delete]: Approved[Delete](token: token)

# The only way to use an approval: it is taken apart here, once.
def spend(approval: Approved[Delete]) -> String:
    let {token} = approval
    return token

def delete_account(id: String, approval: Approved[Delete]) -> String:
    return f"deleted {id} with {spend(approval)}"

export def main() -> Int:
    let approval = approve("a1")
    let one = delete_account("u1", approval)
    let two = delete_account("u2", approval)
    return one.length() + two.length()
```

```text
gate.ms:18:36: type: `approval` is moved here but used again at 19:36; a value has one owner, so pass `approval.clone()` to keep the original, or move it only at its last use
```

What the checker cannot stop today, each verified on main:

- Any module builds `Approved[Delete](token: "x")`, reads `.token`, writes it, or clones it, so the gate is advisory.
- `json.parse[Secret]("{\"value\":\"forged\",\"seal\":{}}")` builds any record structurally; so do `cli.decode[T]`, `processes.decode[T]`, `json.stringify`, and `f"{record}"` (a `Secret` interpolates into a log line).
- A record of scalars copies implicitly, so `Money(cents: Int)` has no owner at all, and a value that was read can be dropped at scope end: a forgotten `deposit` is silent.
- Use after `close` is a runtime `Closed` error (#1537); the stdlib has 29 such cases in `http`, `net`, `fs`, `process`, plus "a second `send_headers` returns InvalidInput". Two proposals to fix it were parked because "only the straight-line case is catchable without typestate".

Non-goals: proving arithmetic facts (amount bounds, index in range) stays with validators in the owning module, faults and tests; a prover; changing `main`; OS sandboxing (capabilities proposal Layer 3); effect annotations; once-callable closures.

## Design

One rule: **a type may declare itself a resource; the checker then applies to it the discipline it applies to memory and host handles.** Humans write the resource types in modules only they may edit; agents write the functions; `ms check` and `ms review` are the reviewer.

### Opaque types (stage 1)

A record with a **hidden field** (a field whose type is not exported, extending the private-field-types proposal, and without a default) is opaque outside its declaring module:

- no construction (`Secret[String](value: ..., seal: ...)`), no field read or write, no destructuring, no `.clone()` unless the module implements `Clonable`;
- no structural operation: `json.parse[T]`, `json.stringify`, `cli.decode[T]`, `processes.decode[T]`, `f"{value}"`, the `@std/test.ms` renderers in `expect_equal` and friends, and any future generic builder or renderer are tagged `structural` (issue #1868) in `stdlib/bindings.json` and reject an opaque type argument at the call site; the module may opt in by implementing an explicit interface (`Display`, a codec);
- equality and hashing are not derived; the module implements `Equal`/`Hashable` if it wants them;
- **move-only**: an opaque value never copies implicitly, even when every field is a scalar, and destructuring it (inside its module) consumes it. So a token with one `Int` field, or a destructor that only reads a part, still gives single use; the review showed both leak when opacity is construction-only.

The module exports the only constructors and accessors. This is what "sealing" meant in the first draft; the review showed construction-only sealing leaks through fields and decoders.

```manuscript
# proposed: checks once private-field-types lands with hidden fields opaque
type Seal:

export type Secret[T]:
    value: T
    seal: Seal

export def secret[T](value: T) -> Secret[T]: Secret[T](value: value, seal: Seal())

export def declassify[T](s: Secret[T]) -> T:
    let {value} = s
    return value
```

```text
# proposed
app.ms:4:17: type: Secret[String] is opaque outside secret.ms; build it with `secret` and read it with `declassify`
app.ms:9:12: type: json.stringify builds its output structurally, which Secret[String] does not allow; implement a codec in secret.ms or pass a plain value
```

### Typestate (stage 1)

`State` is an empty standard interface in `@std/core.ms`. A stateful type bounds its parameter, states are empty types implementing it, and a transition is a function from one state to another:

```manuscript
# `State` and the bound are proposed; the rest checks today.
type Open:
type Authed:

type Connection[S]:
    host: String

interface Querying:
    def query(sql: String) -> String

impl Querying for Connection[Authed]:
    def query(sql: String) -> String:
        return f"{self.host}: {sql}"

def authenticate(conn: Connection[Open], token: String) -> Connection[Authed]:
    let {host} = conn
    return Connection[Authed](host: host)

export def main() -> Int:
    let c = Connection[Open](host: "db")
    let bad = c.query("select 2")
    return bad.length()
```

```text
iface.ms:21:17: resolution: unknown or ambiguous member query on Connection[Open]; available: host
```

Proposed additions, all derived from signatures:

- the diagnostic names the transition when the operation exists at another state: "`query` is available on `Connection[Authed]`; call `authenticate` to get there";
- `ms inspect --states Connection` and `ms diagram` render the state machine (states, transitions, operations per state); `ms review` reports added or removed transitions;
- a transition takes the old state apart (`let {host} = conn`) so the old value is consumed; today destructuring borrows unless a part is moved on, so for opaque types destructuring always consumes (proposed, stage 1); the bound uses the existing `[S: State]` syntax; with `Linear` (stage 2) it also cannot be dropped, so a `Transaction[Open]` must reach `Committed` or `RolledBack` on every path.

Stdlib adoption (stage 3) replaces runtime state errors with states: `HttpExchange[HeadersPending] -> send_headers -> HttpExchange[Streaming] -> Done`, `WebSocket` after `upgrade`, `Subprocess[Running] -> wait -> Exited`, and `Closeable` handles gaining a `Closed` state so use after close is a type error. That is the general form of the three parked close proposals.

### Linear types (stage 2)

`Linear` is an empty standard interface recognized by identity like `Closeable`. `impl Linear for T:` makes `T` linear. Rules:

- **Consumption.** A linear value is consumed by moving it (into a parameter the callee consumes, a field, a return value, a collection element) or by destructuring it, which is allowed only in its declaring module. Taking it apart is the destroy primitive; `let _ = value` is an error.
- **Borrowing stays.** Passing a linear value to a parameter the callee only reads is a borrow, exactly as today (`profile(session, id)` reads the session). The owner must still consume the value before its scope ends. Single use of an approval therefore means: whoever holds it must eventually hand it to the one function that takes it apart.
- **No copy.** No implicit copy even when every field is a scalar; `Clonable` cannot be implemented.
- **No drop.** Every path must consume: scope end (including `main` returning), reassignment of a `var` holding it, an unread binding, a `try` or early `return` that leaves it behind, `Optional.get(default)` / `unwrap_or` with a linear default, `Map` overwrite. A linear field of `var self` may be destructured and must be reassigned before every exit of the method (the `withdraw` body below).
- **Propagation.** A record with a linear field is linear, so an `Account` holding `Money` must itself be settled: the module provides the consuming function (`settle`). `Optional[T]` and `Result[T, E]` of a linear `T` are linear and are consumed by `try`, `if let` and `match`; methods that drop the payload are tagged `drops_element` in `bindings.json` and unavailable.
- **Not allowed in stage 2:** linear type arguments to `List`, `Map`, `Set`, `Deque`, `Queue`, `Channel`, `Task`, `Shared`, and module-level `var` bindings; closures may borrow a linear capture but not move it (so `twice(lambda: eat(t))` is an error at the move). Stdlib collections are audited in stage 3; once-callable closures are out of scope.
- **Generics.** The ownership pass records per type parameter whether a generic body may drop a `T` value (as it records `Consume` today), propagated through nested generic calls. Instantiating such a parameter with a linear type is an error at the call site: "`swallow` drops its parameter `x: T`, so `T` cannot be `Money`". No bound syntax.
- **Faults and cancellation** abort the task; the fault-site drop releases linear values. The guarantee is therefore: *no non-aborting path of a compiling program copies or loses a linear value*. Cancellation is observed at checkpoints, which include loop back-edges, so a linear local live across one is a gap; see Open questions for the two ways to close it.
- `Linear` and `Closeable` are exclusive: closing at scope end is a drop. A closeable handle gets typestate instead.

```text
# proposed
ledger.ms:48:9: type: `m: Money` is not consumed on every path; Money is linear, so move it, pass it to a function that takes it apart, or return it
```

### Worked example: the ledger

Human-owned module (`ledger.ms`), verified with the `Linear` stub:

```manuscript
interface Linear:
    def linear() -> Unit        # stub; empty in @std/core.ms

export type Money:
    cents: Int

impl Linear for Money:
    def linear() -> Unit: ()    # stub line

export type LedgerError:
    case Insufficient
    case Invalid

impl Error for LedgerError:
    def message() -> String: "ledger error"

# The only constructor callers see; a non-positive amount is refused here, once.
export def mint(cents: Int) -> Result[Money, LedgerError]:
    if cents <= 0: return error(Invalid)
    return ok(Money(cents: cents))

export def merge(a: Money, b: Money) -> Money:
    let {cents: x} = a
    let {cents: y} = b
    return Money(cents: x + y)

export type Account:
    id: String
    balance: Money

impl Account:
    var def withdraw(cents: Int) -> Result[Money, LedgerError]:
        let {cents: have} = self.balance
        if cents <= 0 or cents > have:
            self.balance = Money(cents: have)
            return error(Insufficient)
        self.balance = Money(cents: have - cents)
        return ok(Money(cents: cents))

    var def deposit(m: Money) -> Unit:
        let {cents: add} = m
        let {cents: have} = self.balance
        self.balance = Money(cents: have + add)

# Consumes an account at shutdown and reports the balance it held.
export def settle(account: Account) -> Int:
    let {balance} = account
    let {cents} = balance
    return cents

def transfer(var from: Account, var to: Account, cents: Int) -> Result[Unit, LedgerError]:
    let m = try from.withdraw(cents)
    to.deposit(m)
    return ok(())

def run() -> Result[Int, LedgerError]:
    var alice = Account(id: "alice", balance: try mint(50))
    var bob = Account(id: "bob", balance: Money(cents: 0))
    try transfer(var alice, var bob, 30)
    return ok(settle(alice) + settle(bob))

export def main() -> Int: run().get(1)
```

Under stage 2: deleting `to.deposit(m)` is "`m: Money` is not consumed"; depositing twice is the existing "moved here but used again"; `Money(cents: 100)` in another module is "opaque outside ledger.ms"; `m.cents = 1000000` elsewhere is the same error; `transfer(..., -100)` is refused by `withdraw`, the one validator, and the review of that module is the whole review. `run` must `settle` both accounts because `Account` is linear, and a `try` that fails after `alice` exists would drop her balance, so under stage 2 `run` needs an error path that settles too; that is the cost the stage 2 gate measures. Checked arithmetic faults between `withdraw` and `deposit` abort, which the guarantee excludes.

What the checker proves versus what the module is trusted for:

| Policy | Checker enforces | Owning module must get right |
| --- | --- | --- |
| No double spend, no lost money | one owner, no copy, no drop, no outside construction | nothing beyond the types |
| Amounts are positive | nothing | `mint` and `withdraw` validate once |
| An approval serves one action | moved once, taken apart once | `spend` is the only destructor |
| Authenticate before query | `query` exists only on `Connection[Authed]` | `authenticate` checks the token |
| Secrets never reach logs | no field read, no structural render outside the module | `declassify` is the only exit |
| Untrusted input never reaches SQL | `Sql` is opaque; only validators build it | the validator |
| Only these hosts | nothing until stage 4 (`Network.restrict`, runtime) | the manifest |

### Worked example: a web service

Verified today except opacity (single module):

```manuscript
type Untrusted[T]:
    value: T

type Authed:
type Anonymous:

type Session[S]:
    user: String

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
    let {value} = raw
    if value.length() == 0: return error(BadId)
    return ok(UserId(value: value))

def login(session: Session[Anonymous], token: Secret) -> Result[Session[Authed], AppError]:
    let {value} = token
    if value != "ok": return error(Forbidden)
    let {user} = session
    return ok(Session[Authed](user: user))

# Only an authenticated session can read a profile.
def profile(session: Session[Authed], id: UserId) -> String:
    return f"{session.user} viewed {id.value}"

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
web.ms:48:23: type: expected Session[Authed], found Session[Anonymous] (in argument 'session' of profile)
```

With `Untrusted`, `Session`, `Secret` opaque in their own modules: a handler cannot read `path.value`, cannot forge `Session[Authed]`, and cannot log the token. Deletion uses the `Approved[Delete]` gate from the Problem section. In the stdlib, `HttpExchange.path()`, `query()` and header values return `Untrusted[String]` under an opt-in, and the router hands every handler a `Session[Anonymous]`.

### Worked example: a command-line tool

Verified today:

```manuscript
from "@std/fs.ms" import FileSystem, FileSystemError
from "@std/io.ms" import stdout

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
    let {value} = raw
    if value.contains(".."): return error(Outside)
    return ok(SafePath(path: f"{root}/{value}"))

# Removal spends one confirmation and hands back its note for the log.
def remove(fs: FileSystem, target: SafePath, go: Confirmed) -> Result[String, FileSystemError]:
    let {note} = go
    let {path} = target
    try fs.remove(path, recursive: False)
    return ok(note)

def run(fs: FileSystem, root: String, args: List[Untrusted[String]], go: Confirmed) -> Result[Int, Error]:
    let first = try inside(root, args.get(0, default: Untrusted[String](value: "")))
    let first_note = try remove(fs, first, go)
    let second = try inside(root, args.get(1, default: Untrusted[String](value: "")))
    let second_note = try remove(fs, second, go)
    stdout().write(f"{first_note} {second_note}\n").get()
    return ok(0)
```

```text
cli.ms:34:44: type: `go` is moved here but used again at 36:46; a value has one owner, so pass `go.clone()` to keep the original, or move it only at its last use
```

Arguments are `Untrusted` until `inside` accepts them, so `..` never reaches `fs.remove`; a `--force` confirmation covers one removal, so a batch takes a confirmation per item or a separate `ConfirmedBatch` minted by the prompt; the tool only touches the `FileSystem` it was handed (stage 4 narrows it to `root` and rejects `filesystem()` inside `run`).

### Frozen modules (stage 1)

An agent that meets "opaque outside ledger.ms" will add `export def mint_free` to `ledger.ms`. So the guarantee needs `ms review` to report a diff that touches a module listed in `policy/frozen`, or `policy/` itself, as a frozen change, and to report changed exported signatures. Who may make such a change is not a language question: the repository protects `policy/` and the listed modules with CODEOWNERS and a required CI check that fails on a frozen change without an owner approval. `ms review` is the detector; the repository is the gate. `ms review` today produces an authority map and `--diff`; stage 1 verifies it can list exported signatures per module and adds the frozen report, which lands with the first opaque type, not after.

### Capabilities as values (stage 4)

Under a `[permissions]` table in `ms.toml` (the parser accepts only `[project]` and `[aliases]` today, `crates/ms-driver/src/project/manifest.rs:1`), ambient accessors are accepted only in the entry module; other modules receive capabilities as parameters and narrow them with `restrict` (`Network.restrict` exists, `stdlib/net.ms:268-303`; `FileSystem.restrict`, `Commands.restrict` per the capabilities proposal). Host allowlists stay runtime checks. Effects stay inferred for `ms review` and `ms diagram`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-syntax` | accept an empty `interface` body (`State`, `Linear`); no new tokens | parser fixture |
| `crates/ms-check` contracts (`contracts.rs` `fn public`) | hidden fields, opaque rule (construction, access, destructuring, clone) | reject fixtures per operation, per module boundary |
| `crates/ms-check` calls | `structural` tag: reject opaque type arguments to tagged generics | reject: `json.parse[Secret]`, `stringify`, `decode`, `f"{secret}"` |
| `crates/ms-check` resolution | typestate hint naming the transition | conformance `check` fixture with exact text |
| `crates/ms-check` ownership (stage 2) | linear class: no copy, must-consume at every drop site, destructure-in-module, generic drop summaries, closure move rejection | adversarial corpus (below) |
| `crates/ms-lower`, `ms-mir`, codegen, `ms-rt`, ABI | unchanged | existing e2e |
| `stdlib/core.ms` | `interface State:`, `interface Linear:` | prelude fixture |
| `stdlib/bindings.json` | `structural` on `json.parse`, `json.stringify`, `cli.decode`, `processes.decode`, interpolation; `drops_element` (stage 3) | audit test: every generic builder is tagged |
| `stdlib/resources.ms` (new, `.ms`) | `Approved[T]`, `Secret[T]`, `Untrusted[T]`, `Confirmed`, quantity pattern, typestate pattern | `ms test` fixtures |
| `stdlib/http.ms`, `net.ms`, `fs.ms`, `process.ms` (stage 3) | typestate on `HttpExchange`, `WebSocket`, `Subprocess`, `Closeable` handles; `Untrusted` at boundaries | fixtures; the 29 runtime `Closed` tests become reject fixtures |
| `crates/ms-tooling` | `ms inspect --states`, `ms diagram` state view, `ms review` transitions diff and frozen-module check | tooling tests |
| manifest (`ms-driver`, stage 4) | `[permissions]` | manifest tests |
| formatter, lint | unchanged; lint for a linear value passed where a borrow suffices | lint tests |
| LSP, VS Code | hover shows opaque, linear, state | LSP tests |
| documentation | `types/resources.md`; update `types/records.md` construction and visibility, `modules/boundaries.md`, `glossary.md` "resource", "opaque", "state"; `.experts/language.md` (stage 4) | `make docs`, repo-check |
| `bench/agent/` | resource-typed arm with a dated result section | bench-check |
| platform parity | compiler and `.ms` only | CI matrix, nothing gated |

## Alternatives

- Do nothing: the four holes in Problem stay; use after close stays a runtime error; policies stay prose. The agent-bench arm in Staging is the measurement that must beat this.
- Contracts and refinements (withdrawn proposal): shape of a value at one point plus a prover; no proof-rate evidence. An opaque validated type carries the same fact with no prover.
- Effect annotations: redundant once a capability is a parameter.
- Property tests or a runtime policy rule language: sample runs or check at runtime; the ledger needed snapshots and a fuzzer to approximate what ownership gives by construction. Tests stay tests.
- Construction-only sealing (first draft): leaks through fields, decoders and rendering, shown by the review. Opacity is the smallest rule that closes all three.
- A `linear` keyword or field visibility modifiers: more syntax for the same semantics; `Closeable` sets the precedent of a compiler-recognized interface, and hidden fields are already requested.
- Smallest version: stage 1 alone (opaque types, frozen modules, typestate hints) gives consume-once tokens and labels with the move checker that exists today.
- Drawbacks: opaque types need accessor functions; linear values force a consuming path on every branch, including after a second `try` (the review's "every error path needs a refund" case), which is the honest cost of conservation and why stage 2 is gated on measured ergonomics; stdlib collections of linear values wait for stage 3.

## Staging and verification

1. **Consume-once tokens.** Hidden fields and opaque types, `structural` tags, `State` and the transition diagnostic, `ms review` frozen modules and signature diff, `stdlib/resources.ms` with `Approved`, `Secret`, `Untrusted`, `Confirmed`. Gate: an adversarial corpus: reject fixtures for every opacity bypass in Problem and for copy, double destructure and `peek` twice on an opaque token; the drop sites listed under Linear, closures, generics, `var self` and fault/cancel paths enter the corpus as expected-fail fixtures (`tests/conformance/expect-fail.txt`) each naming the stage that flips it; full conformance corpus otherwise unchanged; a `bench/agent/` arm on the approval-token and secret-label tasks with a dated result section comparing bug classes against the untyped arm.
2. **Linear.** `Linear`, must-consume, generic drop summaries, closure rule, `drops_element` for `Optional`/`Result`. Gate: the adversarial corpus turns from "documented" to "rejected"; ergonomics measured on the ledger and on the agent arm; go/no-go recorded here.
3. **Stdlib typestate and containers.** `HttpExchange`, `WebSocket`, `Subprocess`, `Closeable` states; `Untrusted` at HTTP and CLI boundaries behind an option; collection audit. Gate: the 29 runtime `Closed` cases and the `send_headers` twice case become compile errors with their tests converted.
4. **Capabilities as values.** `[permissions]`, accessor rule, `restrict` on `FileSystem` and `Commands`, `.experts` update. Gate: capabilities proposal tests; projects without the table unchanged.

## Review outcome

Blockers from the 2026-10-28 review and their resolution:

1. Ledger violated its own rules, no destroy primitive, linear fields make state linear: destructuring in the declaring module is the destroy primitive; `withdraw`/`deposit`/`merge` rewritten and verified; `Account` is linear on purpose and `settle` consumes it, including before `main` returns.
2. Sealing leaked through decoders, fields, writes, interpolation, `stringify`: replaced by opaque types plus the `structural` tag; `Secret.value` is no longer readable outside its module.
3. Conservation under cancellation: claim restated to non-aborting paths; the module keeps an operation checkpoint-free or compensates (open question).
4. Coverage overclaimed: the trust table states what the checker proves and what the module validates; host allowlists moved to stage 4 as runtime checks.
5. Borrows: always-move dropped; borrows stay as today, the owner must consume before scope end.
6. Closures: moving a linear capture inside a closure is rejected; once-callable closures out of scope.
7. Generics: per-parameter drop summaries, no bound syntax.
8. Other drop sinks: listed; `Channel`, `Task`, `Shared`, module `var`, collections excluded in stage 2; `Confirmed[Batch]` replaced by one confirmation per removal or a separate batch token.
9. Agents edit the sealing module: frozen modules in `ms review` land in stage 1.
10. Vacuous gate: adversarial corpus and agent-bench arm moved into stage 1.
11. Do-nothing evidence: stage 1 ships one token and one label and measures before the kit grows.

Second pass (same day): A. scalar-only tokens copied and read-only destructors left the value reusable: opaque types are now move-only with consuming destructure in stage 1. B. the stage 1 gate asked for rejections stage 1 cannot produce: those fixtures are expected-fail, each naming its stage. C. the ledger's `main` dropped a linear default and discarded a `Result`: rewritten with `try` in `run`, verified. D. who owns `policy/`: the repository (CODEOWNERS plus a required check), `ms review` only detects. Smaller: checked-arithmetic faults are aborts; loop back-edges are checkpoints (open question updated); `[S: State]` is existing bound syntax; test renderers are tagged `structural` (#1868).

## Open questions

- A linear value live across a cancellation checkpoint (a checkpointing call or a loop back-edge): reject it in stage 2 (recommended; `ms check` knows both), or let the type declare a `release` operation the runtime calls on cancellation.
- Whether `State`-bounded parameters may be inferred at construction (`Connection(host: "db")` as `Connection[Open]` when the module names a start state): recommended later, not stage 1.
- Whether the typestate hint should also fire for free-function transitions (`query(c, ...)` where `c: Connection[Open]`): recommended yes, same lookup.
- Accessor rule granularity under `[permissions]`: entry module only (recommended) or modules the table names.
