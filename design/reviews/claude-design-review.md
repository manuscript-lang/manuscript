+++
title = "Claude Code full-design review and adopted fixes"
bookHidden = true
bookSearchExclude = true
weight = 121
+++

# Claude Code full-design review and adopted fixes

[Design index](../_index.md)

Claude Code reviewed the 118 original design pages on 2026-10-11 for simplicity, consistency, implementability, and major omissions. The original independent report is retained below; its line references describe the draft it reviewed. Current concept pages govern the adopted behavior.

## Critical objection resolution

| Finding | Adopted fix and authoritative contract |
| --- | --- |
| C1 — incompatible try errors | Explicit `map_error`; complete [parallel example](../concurrency/parallel.md); exact-error requirements on body fragments and Unit-test matching |
| C2 — unresolved/untypable APIs | Closed [prelude](../standard-library/types/prelude.md), inferred packs, exact `item` label, optional arguments, status/reporting; Background uses one `Result[Unit, String]` callable signature |
| C3 — contract sharing | Plain views remain sequential; explicit [shared views](../core-language/types/contracts.md#shared-contract-views), `Contract & Shareable`, require static receiver sharing proof and preserve it across boundaries; generic behavioral bounds alone do not imply sharing |
| C4 — executable/adapter boundary | Exact [CLI entry and Process](../standard-library/hosts/cli.md), standard stream contracts with declared cleanup, [versioned adapter binding](../modules-and-capabilities/adapters/manifests.md), acyclic schema/native/application packages |
| C5 — missing data APIs | Normative [immutable data operations](../standard-library/data-and-io/operations.md), text/byte conversion, numeric conversion, collection lookup/update |
| C6 — numeric semantics | Checked Int division/remainder, IEEE Float outcomes, finite Decimal coefficient/exponent grid and single rounding, literal/conversion boundaries in [numbers](../core-language/basics/numbers-and-booleans.md) |

All six critical objections are addressed in the design. Observable accepted/rejected cases are in [runtime binding conformance](../compiler/conformance/runtime-bindings.md). These are design fixtures, not compiler test results: the compiler/runtime are not implemented.

The adopted fixes preserve named calls, exact error types, explicit contract views, ordinary references, lexical cleanup, and one function kind. We chose a single Background submission signature instead of Claude's proposed intrinsic overload, explicit shared contract views instead of making every contract shareable, and a finite coefficient/exponent Decimal definition instead of relying on an external package's defaults. Concurrent interface work added bounded generic implementations and overlap rejection; the current examples and host contracts retain those decisions.

Additional fixes close generic function specialization growth, descendant/reporter self-joining shutdown, Equal→Shareable entailment, time operators, known-length destructuring, foreign validation failure handling, panic unwind mechanics, and conservative unknown effects. The whole guide targets 0.1. [Scope](../compiler/conformance/scope.md#outstanding-decisions) tracks unfinished runner, build, adapter, library, and tooling details; the historical priority labels below do not imply that those contracts are complete. Built-in case shorthand continues ordinary lexical lookup; its potential shadowing is intentional and qualified cases remain available.

Claude's full re-review confirmed C1/C2/C4/C5/C6 and identified two additional C3 issues after the concurrent interface changes: plain capability captures in the complete examples, and generic callable-proof laundering. The examples now explicitly require shared contract parameters. Function types cannot satisfy the type-level Shareable bound; generic forwarding and fields erase the separate callable proof, while safe local captures and direct prelude callable arguments preserve it. A dedicated rejection fixture covers the laundering case. Claude's final targeted check confirmed those rules and found one remaining indirect-call bypass: extracting Background.start erased the prelude callback requirement. These proof-requiring standard bindings are now call-only, with matching rejection cases; restricted submission contracts are explicitly deferred. Claude stated that adding this call-only rule closes the callable-sharing loophole. Its targeted pass also confirmed the updated examples and numerical/host/data contracts.

## Original independent review

# Manuscript v0.1 design review

## Verdict

The core language is small and internally consistent: grammar, operators, nominal types, generics, contracts, matching, return completeness and text. A Go implementer could build it as written, and 15 of the 32 historical findings are now closed in the concept pages.

The remaining problems sit where the language meets the runtime. Several load-bearing pieces are handed to an unspecified "trusted manifest": `parallel` typing, standard-library names, adapter binding, sharing for native values, and effect summaries. The six critical objections below all come from that.

### Critical — fix now

| ID | Objection |
| --- | --- |
| **C1** | `try` requires the exact same error type, so every documented `parallel`/`Background` call site is ill-typed. That includes the flagship example. |
| **C2** | The runtime and standard-library APIs (`panic`, `parallel`, `Background`, …) can't be resolved by name, and several can't be typed under the stated type system. |
| **C3** | Nothing says whether contract-typed values are `Shareable`. Either capability-capturing closures are rejected, or the sharing check is unsound. |
| **C4** | Nothing connects a host to running code: no entry contract and no way to create a capability. The planned Go package layout also has an import cycle, and `with` can't accept a contract-typed resource. |
| **C5** | There is no data API. A list whose length depends on input can't be built, Map/Set values can't be created, and numbers and text can't be converted. |
| **C6** | Numeric operator semantics are undefined (Int `/` and `%`, Decimal range) or contradictory (Float faults vs IEEE NaN rules). |

---

## Critical findings

### C1 — `try`'s exact-error rule rejects every documented concurrency call site
**Priority:** CRITICAL (semantic contradiction)

**Evidence**
- `design/core-language/errors/propagation.md:27`: the enclosing function must return `Result[U, E]` with the same exact `E`.
- `propagation.md:25`: error conversion needs an explicit adapter, but no adapter exists anywhere.
- `propagation.md:29`: `try` is rejected in Unit functions and Unit test bodies.
- `design/compiler/frontend/type-checker.md:31,34` restate both rules.
- `design/concurrency/parallel.md:18-21`: one body contains `try parallel(...)` (error type `ExecutionError`), `try resA` (`UserError`) and `try resB` (`OrderError`).
- The same pattern appears at:
  - `concurrency/README.md:8`
  - `core-language/basics/bindings.md:34`
  - `core-language/basics/destructuring.md:10`
  - `concurrency/tasks/operations.md:12`
  - `concurrency/cancellation/deadlines.md:8`
  - `modules-and-capabilities/modules/boundaries.md:24`
  - `standard-library/tasks/background.md:22` (`StartError`)
  - `concurrency/cancellation/requests.md:8`
- `design/compiler/conformance/semantic-tests.md:13` asks tests to verify `let [resA, resB] = try parallel(...)`. Tests are Unit bodies, where `try` is rejected.

**Counterexample.** Wrap `parallel.md:12-21` verbatim in `fn load(...) -> Result[Summary, LoadError]`. Whatever `LoadError` is, at least two of the three `try` sites fail. No return type accepts the canonical example.

**Smallest fix** (keeps the exact-`E` rule)
1. Add a prelude function `map_error[T, E, F](result: Result[T, E], transform: fn(cause: E) -> F) -> Result[T, F]` and cite it from `propagation.md:25` as the explicit adapter. Inference already works under `generics.md:71`, because `transform` is an explicitly typed anonymous function.
2. Rewrite `parallel.md:12-21` as a complete function with an application error alternative:
   ```text
   let [resA, resB] = try map_error(
       result: parallel(tasks: [first, second]),
       transform: fn(cause: ExecutionError) -> LoadError:
           return LoadError.Execution(cause: cause)
   )
   ```
   Fix the other nine sites the same way, or put them inside functions whose error type actually matches.
3. Replace `semantic-tests.md:13` with a helper that returns `Result`, plus a test that `match`es on it. This depends on C2's pack rule (`T` = pack type).

**Acceptance cases**
- The rewritten example type-checks, and `resA` has type `Result[User, UserError]`.
- The same body without `map_error` is rejected at the outer `try` (`ExecutionError` vs `LoadError`).
- `try parallel(...)` directly inside a `test` is rejected; the helper-plus-`match` form is accepted.
- A `transform` written with label `error:` is rejected (labels are part of function identity).

### C2 — Runtime/stdlib APIs have no resolution path and no expressible typing
**Priority:** CRITICAL (resolver and type-checker blocker)

**Evidence — names**
- `design/modules-and-capabilities/modules/declarations.md:13` lists only the intrinsic types and bounds.
- `panic`, `parallel`, `check_cancelled`, `Background`, `ExecutionError`, `Closeable`, `Duration`, `Instant`, `File`, `WorkId`, `StartError` and `OperationId` are neither intrinsic nor importable. `compiler/builds/project-configuration.md:43` forbids bare logical module names, and `:51` leaves package imports unspecified.
- Fixtures still call `panic` without an import (`compiler/conformance/core-language.md:180,584`), while CL-01 makes unknown names resolution errors (`core-language.md:36`).

**Evidence — typing**
- **Heterogeneous packs.** Pack typing is deferred to "trusted API manifests" (`concurrency/parallel.md:30,42`; `compiler/lowering/function-and-task-calls.md:11`). The manifest format is explicitly unspecified (`modules-and-capabilities/adapters/manifests.md:13`). Only literal `tasks:` packs are covered (`type-checker.md:20`), and nothing says what a pack value can do (`standard-library/types/catalog.md:27`, `destructuring.md:14`).
- **`Background.start`.** It accepts `fn() -> Unit` *or* `fn() -> Result[Unit, E]` for any `E` (`background.md:27`). That is an overload plus a generic operation, both excluded (`declarations.md:11`; `contracts.md:51`; `generics.md:65`).
- **Background reporter.** The reporter is "configured" (`background.md:27`, `errors/results.md:45`, `errors/faults.md:39`), but the only constructor shown is `Background(limit: 32)` (`background.md:8`). Records and alternatives can't be formatted either (`text-and-bytes.md:45`), so there is no way to report an arbitrary `E`.
- **Optional arguments.** Trusted APIs may have optional named arguments (`grammar.md:116`, `declarations-and-calls.md:41`), but no page lists which ones.

**Counterexamples**
- `fn f() -> Int: return panic(message: "x")` is a resolution error under `declarations.md:13`, yet CL-17 expects it to be accepted.
- `let p = try parallel(tasks: [a, b])` followed by `helper(p: p)`: there is no type to write for `p`.
- `emails.start(operation: fn() -> Result[Unit, MailError])`: no source signature accepts both this and `fn() -> Unit`, and nothing says where `MailError` goes.

**Smallest fix.** Add one normative page, `standard-library/types/prelude.md`, and extend `declarations.md:13`.
- **Prelude names.** An implicit, non-redefinable set of names. No import form is needed in v0.1. State that for the standard library, "trusted manifest" means this page.
- **`parallel`.** `parallel(tasks: [f1..fn], timeout?: Duration, deadline?: Instant) -> Result[Pack[R1..Rn], ExecutionError]`.
  - `tasks` must be a bracket literal, and each `fi` must be a `Shareable` `fn() -> Ri`.
  - `Pack` has no source spelling. It can be inferred into locals and generic parameters, bound as a match payload, and destructured with exact arity.
  - It can't appear in annotations, parameters or fields, and it has no `Equal`.
- **`Background`.**
  - Constructor: `Background(limit: Int, reporter: fn(failure: BackgroundFailure) -> Unit)`.
  - `start` is the single sanctioned intrinsic overload: either `fn() -> Unit` or `fn() -> Result[Unit, E]` with `E: Shareable`.
  - `BackgroundFailure` is `Failed(work: WorkId, error: String)` or `Crashed(work: WorkId, message: String)`. The `error` text is the deterministic `Type.Case` name, so no formatting protocol is needed.
- **Other signatures.** Add `check_cancelled() -> Unit` and `panic(message: String) -> Never`.

**Acceptance cases**
- `panic` resolves without an import. A module-level `fn parallel` or `type Closeable` is a resolution rejection.
- `parallel(tasks: some_list_variable)` is rejected. Binding `let p = …` and then `let [x, y] = p` is accepted; `let [x] = p` is an arity rejection.
- `start(operation: fn() -> Int)` is rejected. A `MailError.Bounced` result reaches the reporter as `Failed(error: "MailError.Bounced")`.

### C3 — Contract values have no defined `Shareable` status
**Priority:** CRITICAL (soundness, or the flagship examples are rejected)

**Evidence**
- `generics.md:116` and `ownership-and-cleanup/values/sharing.md:11` derive `Shareable` for immutable data and closure captures, and let manifests declare it for native values. Contract types aren't mentioned.
- A contract view wraps the same receiver reference (`contracts.md:57`).
- `parallel` tasks must be shareable (`parallel.md:42`; `scope-checker.md:14`).
- The examples capture contract-typed capabilities: `parallel.md:12-16`, `boundaries.md:21-22`, `background.md:19-20`.
- Non-shareable builders exist (`builders.md:7`), and record fields carry no sharing requirement (`records.md:13-15`).

**Counterexample.** `impl Sink for Collector`, where `Collector` holds a builder (or any manifest-declared non-shareable native). Then `let sink = Sink(value: collector)`, and two `parallel` tasks both call `sink.add(...)`.
- If contract types are `Shareable`, this is a data race on unsynchronized Go state.
- If they aren't, `parallel.md:12-18` and `boundaries.md:21-24` are rejected, because `users`, `orders` and `inventory` are contract-typed captures.

**Smallest fix** (`generics.md:116`, `contracts.md` "Explicit contract views", `sharing.md:11`, `type-checker.md` table)
- Every contract type is `Shareable`.
- `Contract(value: x)` requires `x`'s concrete type to be `Shareable` (derived or manifest-declared).
- Manifests may only bind contracts to shareable natives.
- A contract bound `T: C` does not imply `Shareable`.

**Acceptance cases**
- `Increment(value: Offset(delta: 1))` is accepted.
- A view over a record containing a builder is rejected at the view.
- A `parallel` closure capturing `inventory: Inventory` is accepted; one capturing a builder is rejected.
- `fn f[T: Increment](x: T)` capturing `x` in a task is rejected unless the bound is `Shareable & Increment`.

### C4 — No path from host to running code with real authority
**Priority:** CRITICAL (no executable semantics; adapter build blocker)

**Evidence**
- **Entry.** `project-configuration.md:20` names only an entry *file*. `syntax.md:5` and `grammar.md:120` forbid module initializers. Command and handler registration are unspecified (`hosts/cli.md:15`, `hosts/http.md:15`).
- **Authority roots.** `capabilities/authority.md:7` forbids ambient access, but nothing creates a capability value.
  - `grammar.md:83-86` has no native or extern declaration form.
  - `contracts.md:49` requires an implementation to live in the concrete type's defining module, which native types don't have.
  - `catalog.md:24` lists `File`, `ReadStream` and `WriteStream` without any declaration.
- **Adapter binding.** `manifests.md:7-13` lists what a manifest must describe, but defines no binding target and no format.
- **Package cycle.**
  - `compiler/frontend/pipeline.md:7` and `incremental-compilation.md:9,13` emit one application Go package that imports separately compiled adapter packages.
  - Contracts can mention application types (`contracts.md:9-11`: `Payments` over `Money`, `Receipt`, `PaymentError`).
- **`with` on contracts.**
  - `with` needs an explicit `impl Closeable` (`cleanup/scopes.md:5`, `closeable.md:5`, `scope-checker.md:9`).
  - Contracts have no inheritance (`contracts.md:18`) and no contract-to-contract view (`contracts.md:70`).
  - So a contract-typed resource can never be used in `with`, which blocks the test substitution promised in `authority.md:13`.

**Counterexamples**
1. `src/main.ms` exports `fn run(files: Files) -> Unit`. Nothing says which function runs or who constructs `files`. As a result, none of the required programs in `conformance/programs.md:11-16` can be written.
2. A Go adapter for `Payments.charge(amount: Money) -> Result[Receipt, PaymentError]` must name the generated `Money` and `Receipt` types. Those live in the application package, which imports the adapter, so Go rejects the build with "import cycle not allowed".
3. A test fake for `Files` must return a `File`.
   - If `File` is a native concrete type, the fake can't construct one.
   - If `File` is a contract, `with file = try files.open(...)` is rejected.

**Smallest fix** (CLI only)
- **Entry contract** (`project-configuration.md`, `cli.md`).
  - The entry module exports exactly `fn main(process: Process) -> Int`. The return value is the exit status (0–125; anything else is a fault).
  - A fault exits with code 70 after cleanup, with diagnostics on stderr.
  - SIGINT or SIGTERM cancels the run context, the program unwinds, and it exits with 130.
- **Root capabilities.** `Process` is a prelude record and the only root of authority:
  - `arguments: List[String]`
  - `environment: Map[String, String]`
  - `stdin: ReadStream`, `stdout: WriteStream`, `stderr: WriteStream`
  - `files: Files`
  - `clock: Clock`
- **Adapter shape** (`manifests.md`, `incremental-compilation.md`).
  - An adapter ships an interface `.ms` module containing only contracts and data over intrinsic/prelude types and its own declarations.
  - Its manifest maps each operation to a Go symbol, with effects and sharing.
  - Each interface module is generated into its own Go package. The adapter imports it, and the app imports both, so the graph is acyclic. Application types can't appear in adapter contracts.
- **`with` rule** (`scopes.md`, `closeable.md`, `scope-checker.md`).
  - Also accept a contract type that itself declares `fn close() -> Unit`, and register that operation. `Closeable` qualifies trivially.
  - `File`, `ReadStream` and `WriteStream` become standard contracts, so source fakes work.

**Acceptance cases**
- A missing or wrong-signature `main` is a compile error that names the entry contract.
- A program that prints its argument count exits 0.
- A fault inside `with` closes the resource exactly once, then exits 70.
- SIGINT during `parallel` joins the group, runs cleanup, and exits 130.
- An interface module that imports an app module is rejected. The fixture's generated Go builds without cycles.
- `impl Files for FakeFiles` works under `with`. `with x = Offset(...)` is rejected.

### C5 — No minimal data API
**Priority:** CRITICAL (complete-program blocker)

**Evidence**
- No collection constructors or updates: `types/collections.md:54`, `builders.md:9`.
- Lookups and updates are deferred to "declared library operations" (`expressions.md:43`) that don't exist.
- No conversions: `numbers-and-booleans.md:25,40`, `compatibility.md:28` ("when available"), `text-and-bytes.md:70-72`.
- The fixtures deliberately avoid these APIs: `core-language.md:409,419,652`.
- `loops.md:26-30` iterates Map and Set values that source code can't construct.

**Counterexamples**
- `fn positives(values: List[Int]) -> List[Int]` can't be written: there is no append and no builder.
- `fn mean(values: List[Int]) -> Float` can't be written: there is no Int→Float conversion.
- `fn second(args: List[String]) -> Optional[String]` can only use exact-length destructuring, which faults otherwise.
- No `Map` value can exist, so `loops.md:35` can only ever see host input.

**Smallest fix.** Add compiler-defined members on the intrinsic types. Member-call syntax already exists, and users can't extend these. All of them return new immutable values.
- **`List[T]`:** `length() -> Int`, `get(index: Int) -> Optional[T]`, `append(value: T)`, `concat(values: List[T])`.
- **`Map[K, V]`:**
  - `Map[K, V]()` constructs an empty map. Type arguments can come from the expected type (`generics.md:93`).
  - Members: `length`, `get(key:) -> Optional[V]`, `contains(key:)`, `with_entry(key:, value:)`, `without(key:)`.
  - A replacement keeps the key's first insertion position.
- **`Set[T]`:**
  - `Set[T]()` constructs an empty set.
  - Members: `length`, `contains(value:)`, `with_value(value:)`, `without(value:)`.
- **String and Bytes:** `String.byte_length()`, `String.to_bytes()`, `Bytes.length()`, `Bytes.to_text() -> Optional[String]`, `String.parse_int() -> Optional[Int]`.
- **Numeric:**
  - `Int.to_float()` (round half to even) and `Int.to_decimal()`.
  - `Float.truncate_to_int() -> Optional[Int]` (returns `none` for NaN, ±∞ and out-of-range values).
  - `Decimal.to_float()` and `Decimal.truncate_to_int() -> Optional[Int]`.
- **Deferred:** builders and scalar/grapheme indexing. O(n) copying is acceptable in v0.1.

**Acceptance cases**
- `positives(values: [3, -1, 2]) == [3, 2]`.
- `[1].get(index: 5) == none`.
- After inserting `a`, then `b`, then replacing `a`, the map iterates `a→3, b→2`.
- `"é".byte_length() == 2`.
- Bytes containing `0xFF` give `to_text() == none`.
- `1e300.truncate_to_int() == none`.
- A user `impl` on `List` is rejected.

### C6 — Numeric operator semantics are undefined or contradictory
**Priority:** CRITICAL (the backend can't emit `/`, `%` or Decimal operations deterministically)

**Evidence**
- `numbers-and-booleans.md:25` says "overflow and invalid operations produce programming faults". That conflicts with the IEEE binary64 representation (`:19`), the NaN/±0 equality rules (`equality-and-hashing.md:11`) and the non-finite formatting rules (`text-and-bytes.md:66`).
- `numbers-and-booleans.md:40` leaves the Decimal exponent range and exceptional values open.
- `expressions.md:50-51` defines typing only.
- `core-language.md:67` says division by zero faults but says nothing about signs.

**Counterexamples** (each has two plausible answers)
- `-7 / 2`: −3 or −4?
- `-7 % 3`: −1 or 2?
- `MIN / -1`: what happens?
- `1.0 / 0.0`: a fault, or +∞? If it faults, the NaN equality rule is dead text.
- `1d / 3d`: how many digits?
- `1e6144d * 10d`: overflow behavior?
- A Decimal literal with 37 significant digits: accepted, rounded or rejected?

**Smallest fix** (`numbers-and-booleans.md`, `value-representations.md:11-12`)
- **Int.**
  - `/` truncates toward zero, and `%` has the sign of the dividend.
  - A zero divisor faults, as do `MIN / -1` and `-MIN`. `MIN % -1 == 0`.
- **Float.** IEEE default semantics with no faults. Limit the `:25` fault rule to Int and Decimal.
- **Decimal.**
  - Use decimal128 parameters: 34 digits, exponent range −6143 to 6144, round half to even on every operation.
  - Overflow, division by zero and `0/0` fault. Underflow goes to subnormal or zero without a fault.
  - A literal with more than 34 digits, or out of range, is a compile error.

**Acceptance cases** (use parameterized runtime inputs so constant folding can't hide behavior)
- `-7/2 == -3`; `-7%3 == -1`; `MIN/-1` faults.
- `1.0/0.0` formats as `Infinity`; NaN is not equal to itself.
- `1d/3d` formats as `0.3333333333333333333333333333333333`.
- Decimal overflow faults; a 35-digit literal is rejected.

---

## Important nonblocking findings

**I-01 — Does `Equal` imply `Shareable`?**
- **Evidence.** `generics.md:31` says "equality requires sharing eligibility" but isn't explicit about bounds. `equality-and-hashing.md:36-39` declares `Tree[T: Equal]` with a `List[Tree[T]]` field. That only checks under `generics.md:108` if `Equal` implies `Shareable`. Meanwhile `core-language.md:271,277` writes the redundant `Shareable & Equal` and `Box[T: Shareable]`.
- **Fix.** Make the chain explicit in the bounds table: `Hashable` ⇒ `Equal` ⇒ `Shareable`, for both satisfaction and body assumptions. Fields alone impose no bound.
- **Accept.** `Tree[T: Equal]` and `fn f[T: Equal](x: T) -> List[T]` are accepted; `fn g[T](x: T) -> List[T]` is rejected.

**I-02 — Duration/Instant arithmetic contradicts the closed operator table** (fix together with C2)
- **Evidence.** `deadlines.md:10` writes `clock.now() + 2.seconds`, but `expressions.md:5,49-52,66` is closed and numeric-only. `numbers-and-booleans.md:58` and `grammar.md:36` don't list the units or say whether `n.seconds` works on a non-literal.
- **Fix.** Add these rows: `Duration ± Duration`, `Instant ± Duration`, `Instant − Instant → Duration`, and same-type ordering. Allow `.milliseconds`, `.seconds` and `.minutes` on any Int (overflow faults). Add `Clock.now() -> Instant`.
- **Accept.** The deadlines example type-checks; `2.seconds + 1` and `Instant + Instant` are rejected.

**I-03 — "Statically known" destructuring length is undefined**
- **Evidence.** `destructuring.md:16` vs `core-language.md:142,145`.
- **Counterexample.** `let xs = [1, 2]` followed by `let [a] = xs`: compile error or runtime fault?
- **Fix.** The length is statically known only when the initializer is syntactically a list literal or a pack.
- **Accept.** `let [a] = [1, 2]` is rejected; the `xs` version is accepted and faults at runtime.

**I-04 — Effect and capability promises exceed the specified machinery** (historical M05/M06)
- **Evidence.** `effects.md:7` says "an operation contract bounds declared behavior", but no syntax exists. `boundaries.md:5` refers to "accepted capabilities" without defining them. See also `architecture-diffs.md:7`.
- **Fix.**
  - A capability is a value whose static type is an adapter-interface contract (C4), or that reaches one.
  - The effect set is {read, write, external-call, unknown}. Dynamic dispatch or a function-value call contributes `unknown`, never the empty set.
  - Replace "bounds" with "reports".
- **Accept.** The system view lists `Payments` but not a pure `Formatter`, and dynamic dispatch shows up as `unknown`.

**I-05 — Foreign value validation has no failure path** (historical M08)
- **Evidence.** `value-conversion.md:7,11`; `cleanup-and-faults.md:9`.
- **Counterexample.** An adapter returns invalid UTF-8, nil for a non-optional value, an unknown tag, or a `uint64` above `MaxInt64`.
- **Fix.** The generated wrapper validates the value. A violation is a fault with operation, type and path diagnostics, reported as `Crashed` at API boundaries. Untrusted data stays `Bytes` and goes through `Bytes.to_text()`.
- **Accept.** One fixture adapter per invalid value class.

**I-06 — Unwinding faults and cancellation in Go is underspecified**
- **Evidence.** `scopes.md:19`, `cleanup-and-faults.md:5,9`, `exit-order.md:7-10`.
- **Counterexample.** A fault three frames below a nested `with`. In Go, only a `defer` runs during a panic, so "explicit unwind paths" alone skip `close()`. A secondary cleanup fault also needs `recover` inside a deferred function.
- **Fix.**
  - Faults and cancellation are typed Go panics.
  - Each function with cleanup scopes keeps a scope stack drained by one deferred handler. Normal exits pop the stack explicitly.
  - Cleanup runs under `context.WithoutCancel`.
  - Stack exhaustion and out-of-memory are host failures with no cleanup guarantee; say so.
- **Accept.** Inner-then-outer close, each exactly once; secondary faults are retained.

**I-07 — `ExecutionError.Cancelled` has no source in parallel groups**
- **Evidence.** `cancellation/propagation.md:7`, `joining.md:18` and `timeouts.md:11` assume an "independent child cancellation", but no source construct can cancel a single child.
- **Fix.** Name the only source of that cancellation, or declare `Cancelled` unreachable for `parallel` in v0.1.
- **Accept.** A fixture shows that caller cancellation unwinds the caller rather than returning `Cancelled`.

**I-08 — Test discovery and runner contract** (historical TOOL-01 remainder)
- **Evidence.** `type-checker.md:34`, `semantic-tests.md:9`, `grammar.md:102,118`.
- **Counterexample.** Do tests in a module the entry doesn't import run? Are duplicate test names allowed? Do tests end up in production builds? How does a fixture expect a fault (`core-language.md:141`)?
- **Fix.**
  - `ms test <ms.toml>` compiles every `.ms` file under `project.source`.
  - A test's ID is (root-relative path, name); duplicate names in one module are rejected.
  - Tests are excluded from builds, and each test runs in an isolated run context.
  - Expected faults are declared to the runner, not in source.
- **Accept.** A test in an unreachable module runs, and one failing test doesn't stop the others.

**I-09 — The required programs depend on unspecified APIs, and there is no v0.1 gate**
- **Evidence.** `programs.md:11-16` requires programs that need APIs with no signatures:
  - streams (`streams.md:7-15`)
  - queues (`queues.md:15`)
  - pools (`synchronized-state.md:11`)
  - HTTP (`http.md:15`)
  - subprocesses
  - a debugger session (`debugger-integration.md:13`)

  Meanwhile `README.md:31` claims the guides together specify v0.1.
- **Fix.**
  - The v0.1 gate covers the C4 CLI with file and stdio streams (with read/write signatures), `parallel`, `Background`, the cleanup-fault program and the acquisition-race program.
  - Move HTTP, subprocess draining, queues, pools and the debugger session to a labeled next milestone.
  - Add normative/deferred status labels to each guide index.
- **Accept.** Every v0.1 program fixture is complete source plus a manifest plus an expected transcript, using only specified APIs.

**I-10 — Project containment, dependencies and locking** (historical M03/M10)
- **Evidence.** `project-configuration.md:22,24,37,49,51`; `reproducibility.md:7-9`.
- **Counterexample.** `import X from "../../other/x.ms"` points outside the project. Whose aliases apply, and what gets pinned?
- **Fix.**
  - All imports and alias targets must resolve inside the project root after symlink resolution.
  - v0.1 has no third-party dependencies.
  - Specify `ms build|check|test <ms.toml>`.
  - An `ms.lock` records the compiler, Go toolchain, runtime and adapter versions with checksums. A mismatch fails the build, and unknown manifest keys are rejected.
- **Accept.** Escapes via `../` or symlinks are rejected; a changed adapter checksum fails the build.

**I-11 — Tooling promises lack minimal invariants** (historical TOOL-04/05/06/07)
- **Evidence.** `formatting.md:7`, `structural-editing.md:7-13`, `metadata.md:7,13`, `diagnostics.md:13`.
- **Counterexample.** A three-file rename partially applies after one importing file changes; two runs of the same binary are indistinguishable in traces.
- **Fix.** Either move these tools out of the v0.1 gate, or add:
  - **Formatter:** idempotent, keeps comments, LF line endings with a final newline, no write on invalid input.
  - **Structural edits:** guard every file read or touched plus `ms.toml`; all-or-nothing; validate before writing.
  - **Metadata:** a static manifest (spans as UTF-8 byte half-open ranges) kept separate from per-run records (run ID).
  - **Diagnostics:** a stable rule code plus a primary span.
- **Accept.** Formatting twice produces no diff; a stale referenced file causes zero writes.

**I-12 — Built-in case names aren't reserved**
- **Evidence.** `declarations.md:13` reserves only type names, and `alternatives.md:29` does ordinary lookup first.
- **Counterexample.** A module-level `fn error(message: String)` turns every `error(cause: …)` in that module into an "unknown argument" error. A user `case none` makes every bare `none` ambiguous.
- **Fix.** Make `some`, `none`, `ok` and `error` non-redefinable as module names, imports and case names.
- **Accept.** Both declarations are rejected at resolution.

**I-13 — Editorial**
- The definite-initialization rules (`conditionals.md:49`, `ownership-and-cleanup/values/control-flow.md:9`, `scope-checker.md:13`) are vacuous given `bindings.md:44`. Replace them with "initialized at declaration".
- The status text in `README.md:35` and `reviews/language-completeness.md:5-9` is stale. Add the status table below to the review.

## Intentional deferrals (checked; each just needs an explicit "deferred" label)

- **Types and modules:** opaque exports, import renaming and re-exports, generic impls and methods, orphan implementations.
- **Syntax:** user iteration protocols, labeled loops, raw and multiline strings, default and variadic parameters, Map/Set literal syntax.
- **Data:** builders, grapheme/scalar indexing, Float hashing, collection hashing.
- **Effects and concurrency:** user effect annotations, general type-pack syntax, actors, detached tasks, forced termination.
- **Tooling formats:** diagnostic schema, edit wire protocol, debugger watch evaluation.

None of these blocks v0.1.

## Historical review (`reviews/language-completeness.md`) checked against current pages

| Finding | Status now | Current evidence / where tracked |
| --- | --- | --- |
| CORE-01 grammar | Resolved | `grammar.md:7-173` |
| CORE-02 operators | Resolved | `expressions.md:11-58` |
| CORE-03 numerics | Partly open | Literals resolved (`numbers…md:29`); behavior → **C6**, conversions → **C5** |
| CORE-04 text | Resolved | `text-and-bytes.md:7-66`; Bytes construction → C5 |
| CORE-05 constructor context | Resolved | `compatibility.md:30-61`, `alternatives.md:29,53` |
| CORE-06 equality | Resolved | `equality-and-hashing.md:11-41`; bound entailment → I-01 |
| CORE-07 generics | Resolved | `generics.md:48-110` |
| CORE-08 recursion | Resolved | `records.md:63-81` |
| CORE-09 contracts | Resolved | `contracts.md:16-86`; sharing → **C3**, `with` → **C4** |
| CORE-10 function types / captures | Resolved | `compatibility.md:17`, `function-values-and-closures.md:20-45` |
| CORE-11 Unit/Never | Resolved | `declarations-and-calls.md:71-96` |
| CORE-12 match | Resolved | `pattern-matching.md:22-60` |
| CORE-13 iteration | Resolved | `loops.md:22-43` |
| M01 public closure | Resolved | `declarations.md:36-49` |
| M02 names / coherence | Resolved | `declarations.md:11-17`, `contracts.md:47-53`; case names → I-12 |
| M03 containment | Open | `project-configuration.md:37,49,51` → I-10 |
| M04 stdlib resolution | Open | `declarations.md:13` → **C2** |
| M05 capability classification | Open | `authority.md:7` → I-04 / C4 |
| M06 effects | Open | `effects.md:7` → I-04 |
| M07 manifests / package cycle | Open | `manifests.md:13`, `pipeline.md:7` → **C4** |
| M08 foreign validation | Open | `value-conversion.md:7-11` → I-05 |
| M09 entry / host | Open (module-init part resolved) | `cli.md:15`, `http.md:15` → **C4**, I-09 |
| M10 builds / test discovery | Open | `reproducibility.md:7`, `type-checker.md:34` → I-08, I-10 |
| M11 data API | Open | `collections.md:54`, `builders.md:9` → **C5** (raised to critical) |
| TOOL-01 tests | Partly resolved | Static Unit contract adopted (`type-checker.md:34`); runner → I-08 |
| TOOL-02 core oracle | Largely resolved | `core-language.md` CL-01…18; numeric runtime fixtures pending (C6) |
| TOOL-03 program fixtures | Open | `programs.md:9-16` → I-09 |
| TOOL-04 edit transactions | Open | `structural-editing.md:7-13` → I-11 |
| TOOL-05 metadata split | Open | `metadata.md:7,13` → I-11 |
| TOOL-06 debugger | Open | `debugger-integration.md:13` → I-09 / I-11 |
| TOOL-07 formatter / diagnostics | Open | `formatting.md:7`, `diagnostics.md:13` → I-11 |
| TOOL-08 status / gates | Partly resolved | Core marks normative pages (`core-language/README.md:9`); other guides → I-09 |

## Coverage

All 118 Markdown pages were read in full, plus 3 site files. No files were edited and no code was run.

- **Top level:** `design/README.md`, `reviews/language-completeness.md`
- **core-language/** (29): `README`
  - basics: `README`, `syntax`, `grammar`, `expressions`, `bindings`, `destructuring`, `numbers-and-booleans`, `text-and-bytes`
  - types: `README`, `records`, `alternatives`, `optionals`, `collections`, `equality-and-hashing`, `contracts`, `generics`, `compatibility`
  - functions: `README`, `declarations-and-calls`, `function-values-and-closures`
  - control-flow: `README`, `conditionals`, `loops`, `pattern-matching`
  - errors: `README`, `results`, `propagation`, `faults`
- **ownership-and-cleanup/** (12): `README`
  - values: `README`, `references`, `sharing`, `aggregates`, `control-flow`
  - cleanup: `README`, `scopes`, `closeable`, `exit-order`, `cleanup-faults`, `resource-release`
- **concurrency/** (16): `README`, `parallel`
  - tasks: `README`, `operations`, `return-values`, `lifetimes`, `joining`
  - cancellation: `README`, `requests`, `propagation`, `timeouts`, `deadlines`
  - runtime: `README`, `atomic-transitions`, `completion`, `adapter-contexts`
- **standard-library/** (14): `README`
  - types: `README`, `catalog`
  - tasks: `README`, `background`
  - data-and-io: `README`, `streams`, `queues`, `synchronized-state`, `builders`
  - hosts: `README`, `cli`, `http`
- **modules-and-capabilities/** (11): `README`
  - modules: `README`, `declarations`, `boundaries`
  - capabilities: `README`, `authority`, `effects`
  - adapters: `README`, `manifests`, `value-conversion`, `cancellation`
- **compiler/** (20): `README`
  - frontend: `README`, `pipeline`, `type-checker`, `scope-checker`, `typed-ir`
  - lowering: `README`, `function-and-task-calls`, `value-representations`, `evaluation-order`, `cleanup-and-faults`
  - builds: `README`, `project-configuration`, `reproducibility`, `incremental-compilation`
  - conformance: `README`, `core-language`, `semantic-tests`, `programs`, `v0.1-scope`
- **developer-tooling/** (14): `README`
  - source: `README`, `formatting`, `structural-editing`, `diagnostics`
  - debugging: `README`, `metadata`, `source-mapping`, `debugger-integration`
  - diagrams: `README`, `views`, `flow`, `architecture-diffs`, `traces`
- **Site files** (no design content): `_layouts/website/page.html`, `assets/diagrams.js`, `styles/website.css` (first 40 lines).

**Not read:** `design/assets/mermaid.min.js`, a vendored, minified third-party Mermaid bundle with no design content; I only saw it in search hits. There are no other gaps.
