+++
title = "Read-only accessors: design proposal"
+++

# Read-only accessors and the approved standard-library migration

Status: **approved design; implementation independently reviewed; draft PR authorized; merge held**.
Baseline: `main` at `477b4c916cd772f0f7f7229dc502e99385c855d0` (2026-10-14).
The earlier audit used `4eda0e22`; both checkouts contain 44 standard modules.
The independent reviewer approved revised design commit `46c46a29105e1aabb969d22cce96825b52dc0b8a`; the parent relayed approval before implementation. The initial implementation integrated `main` at `1383851e`, including #497, source-owned standard documentation from #501, and the independent scalar/native-call improvements from #503. The performance comparison uses that revision as its method-era baseline; the original audit partition below remains historical evidence. Pre-publication integration also includes main through #515 (`b2a288b1`). See the [implementation verification record](read-only-accessors-verification.md) for executed checks and measurements.

The user approved designing consistent live read-only accessors for the precise
inventory below. `Error.message()` and **every implementation of it remain
methods**. The parent appointed an independent skeptical reviewer and relayed explicit
approval before implementation. The design author did not self-approve.
The user authorized pushing the branch and opening a draft PR; merge remains held for parent coordination. Keep the work separate from collection
prelude PR497, debugger work, and the stopped broad performance branch.

## Problem and decision

Today `items.length()` observes a value, but `items.length` binds a callable.
Ordinary `name: Type` fields are mutable storage. Native constructor fields can
describe inputs without even being readable fields: Queue.capacity and
Synchronized.value are examples. Neither a stored field nor a constructor
snapshot can represent a live computed read safely.

Add one member category, an **accessor**, with declaration syntax
`get name -> Type`. Read it with `receiver.name`. It uses the same annotated
syntax tree, member resolution, implementation evidence, execution rules and
visibility machinery as other operations. It has no assignment operation and
does not manufacture a bound function on a read. Source implementations, native
types and interface/generic access all implement this same contract.

The concrete benefits are consistent source spelling and removal of unnecessary
binding/dispatch on statically resolved reads. Syntax alone is not a performance
improvement. Performance acceptance requires the emitted operations and focused
measurements described below; this proposal makes no numeric speedup claim.

## Syntax and examples

`get` is contextual at an operation declaration head, not a newly reserved word.
Existing `fn get(...)`, `.get(...)`, fields named `get`, and local names continue
to parse. An accessor has an explicit result type, no parentheses, arguments,
defaults, accessor-specific type parameters, initializer, setter or static form.
It may use its receiver type's parameters. It is not an anonymous function or a
new kind of function value.

Proposed source syntax (a complete example for future acceptance tests):

```manuscript
import panic from "@std/faults.ms"

interface Sized:
    get length -> Int

type Buffer:
    items: List[Int]

impl Sized for Buffer:
    get length -> Int:
        return self.items.length

fn size[T: Sized](value: T) -> Int:
    return value.length

test "accessors are live":
    let buffer = Buffer(items: [])
    if size(buffer) != 0:
        return panic("new buffer was not empty")
    buffer.items.append(7)
    let view = Sized(value: buffer)
    if view.length != 1:
        return panic("accessor missed a mutation")
```

Accessor bodies use ordinary callable suites, explicit returns, implicit `self`,
cleanup and compatible `try`. Inline bodies use `get length -> Int: return ...`.
Application implementations live in `impl` blocks, just like current methods;
this does not add inherent methods/accessors to application `type` blocks.
Native declarations use the same receiver-declaration location as current native
methods, with an ordinary empty colon body, for example this declaration fragment:

```manuscript
export type Queue[T]:
    capacity: Optional[Int] = none
    get length -> Int:
    get is_empty -> Bool:
    get peek -> Optional[T]:
```

Only checked, pinned native binding authorization permits those empty bodies.
There is no `native` keyword or permissive library-only parser. Interfaces use
`get length -> Int` without a colon/body. An implementation must supply `get`,
not `fn length() -> Int`; the two declarations are different contracts even
though their implementation bodies both have zero explicit parameters.

Minimal grammar additions:

```ebnf
AccessorSignature = "get", Name, "->", Type, NEWLINE ;
AccessorDeclaration = "get", Name, "->", Type, FunctionSuite ;
```

Include AccessorSignature among interface operations and AccessorDeclaration
among implementation operations and native receiver declarations. Reject them
at module scope and in function-type syntax. Keep the existing field grammar.

## Alternatives considered

| Alternative | Assessment |
| --- | --- |
| Keep methods; optimize their calls only | Smallest implementation and a valid dispatch-only optimization. It preserves old function references but does not meet the requested consistent property syntax. Use it as the performance control, not the API decision. |
| Replace getters with ordinary/native constructor fields | Incorrect for mutation, head replacement, guard validation and synchronization. Constructor inputs are not live readable state. A new field also risks allowing assignment or changing constructors, equality and clone behavior. |
| Auto-invoke every zero-argument method on a member read | Breaks method values, Error.message, conversions and actions. A callable's arity cannot express the requested distinction. |
| Permit both getter and getter() indefinitely | Creates two public spellings and ambiguous migration/function-value behavior. Prefer one accessor API with positioned old-call diagnostics. |
| Builtin-only property names or a special native accessor syntax | Avoids some parser work but leaves source implementations, interfaces and generics incoherent. Current hardcoded Int properties demonstrate the special case to eliminate. |
| `fn length -> Int` without parentheses | Adds no contextual keyword and can reuse bodies, but makes a missing parameter list silently choose different member semantics. `get` states the read contract directly; ordinary fn declarations keep their call/value rules. |
| `property`, `readonly` fields, decorators, or getter/setter blocks | More syntax or storage ambiguity than this feature requires. A contextual get head with the existing arrow/result/body forms is sufficient. Setters and stored immutable fields are separate proposals. |

The chosen get form adds one explicit member distinction and no new callable
value kind. Its cost is real: parser/checker/tooling work and a breaking migration.
The independent reviewer should reject it if the unified implementation/evidence
path cannot satisfy the semantics below; surface syntax alone is insufficient.

## Read semantics

1. Evaluate the receiver once, at the member expression's position in ordinary
   left-to-right evaluation. Resolve using checked identities and invoke that
   accessor once. A chain such as `make_response().metadata.headers` evaluates
   `make_response` once and reads each subsequent member in order.
2. Every evaluated occurrence performs a fresh read. There is no memoization,
   lazy-once value, constructor snapshot, purity assumption, or common-subexpression
   elimination. Short-circuiting and untaken branches skip the read normally.
   Existing internal algorithms such as String's immutable text-shape cache are
   preserved; no new accessor-result cache is introduced.
3. The expression's type is the declared result after receiver/interface
   substitution. No Optional unwrap, Result flattening, conversion, clone or
   freeze is implicit. Empty first/last/peek returns `none`, including when the
   element type is itself Optional. Boolean classifiers retain their meanings.
4. Read-only describes the member, not deep immutability or a purity proof.
   `x.length = 3` is rejected for both `let` and `var` receivers. A returned mutable
   reference still aliases the original. `response.metadata.status = 201` and
   `guard.value.append(7)` can be valid; assigning `response.metadata` or
   `guard.value` is not. Guard payload replacement remains `guard.set(value)`.
5. Accessors follow existing operation visibility, explicit nominal `impl`
   relationships, local-extension coherence and generic bounds. A mutable field
   or a zero-argument method does not automatically satisfy an accessor contract.
   Accessor results do not extend resource or lock lifetimes.
6. Names are selected before considering result types. Two visible contracts
   offering the same name remain ambiguous and need an explicit interface view.
   A field/accessor collision on a source receiver is rejected when introducing
   the accessor implementation; do not silently hide it behind the field. A
   contract cannot declare a method and accessor with the same name. Existing
   field/method behavior outside this new category is unchanged.
7. A source accessor can run ordinary code, suspend, fault, or return a Result.
   No new effect system or purity restriction is introduced. The approved native
   inventory is observational; that does not license treating all source reads
   as pure or removing calls with unused results. Bare accessor expression
   statements follow existing expression-statement rules; use a binding when a
   value needs to be read and discarded explicitly.

### Lifetimes, synchronization, cancellation and faults

Retain the existing operation body and checks, factoring them into receiver-only
helpers rather than replacing them with raw host field reads:

- List/Map/Set and local Queue/PriorityQueue reads observe the authoritative
  mutable handle. Local queues acquire no new implicit mutex; shared access
  still requires the same Synchronized policy for reads and writes. Peek neither
  dequeues nor invokes the priority comparator. List first/last and queue peek
  preserve the returned element's reference identity.
- SynchronizedGuard.value holds the cell mutex and verifies that this exact
  guard is still the holder on every read. Closed/stale aliases and a guard
  released during wait must fault as current get does. Do not cache the payload
  in the guard or reuse it after close/reacquisition. Preserve current get's
  validation; do not silently impose wait/notify's additional owner restriction
  on value reads. wait/notify/cancel/alias-close behavior is otherwise unchanged.
- Logger.level reads the current threshold under its existing mutex. Directory
  and TemporaryDirectory path retain their existing mutex protection.
- ClientResponse.metadata reads the **current head** on every access. Changing
  head detaches earlier aliases and subsequent reads yield the replacement.
  ResponseBody.metadata and HttpExchange.headers preserve shared metadata/header
  aliases. No headers, record, collection membership or body is copied.
- Preserve current post-close availability. ResponseBody metadata remains
  available after close. Current Directory/TemporaryDirectory paths, connection
  addresses, listener/datagram/server addresses, exchange request metadata and
  WebSocket subprotocol reads precede their I/O closed-state gates; keep that
  behavior. Do not introduce blanket closed-resource faults or bypass checks on
  any accessor whose existing body does validate a handle.
- Preserve expected failures as declared values and programming faults as faults,
  with operation/source attribution. Rename diagnostic remedies to valid new
  syntax (for example `check is_some first`); retain existing message identities
  such as the closed-guard diagnostic and all Error.message output.

Cancellation is path-specific, not an excuse to erase runtime semantics. Current
direct collection/String helpers check admission; bound native functions also
check delivery after their body, which can matter after a contended mutex.
Receiver-only replacements must retain their path's admission/delivery behavior,
including a check after waiting for a mutex where the old wrapper checked on
return. Redundant adjacent checks with no intervening observable work may be
factored, but a delivery check may not disappear. Preserve the absence of a
cancellation check on the current bare Int unit properties.

Direct source recursion and dynamic entries that use Enter retain its sampling
(every 256 entries); other source/dynamic wrappers retain their current eager
depth/admission/delivery checks. Loop polling retains its sampling (every 64
ticks). Dynamic method dispatch currently has its own cancellation admission
check; equivalent accessor dispatch retains it. Direct source accessors follow
direct source callable rules, including recursive-cycle analysis. Do not add eager
cancellation to every source member or restore per-call frame defers. Keep
shielded cleanup, propagation, return, depth accounting, fault frames and source
line directives. Accessor bodies acquire no new disposal contract.

## Exact standard-library migration inventory

These are **56 existing receiver methods in 14 declaration files**. Each row
lists every approved member explicitly; comma-separated names are separate
members with the stated result. Unless an arrow is shown, keep the name and
remove call parentheses at reads. No other method is approved by similarity.

| Declaration file | Receiver | Existing method(s) -> accessor(s) | Result |
| --- | --- | --- | --- |
| `pkg/stdlib/collections.ms` | List[T] | length(), is_empty() -> length, is_empty | Int, Bool |
| same | List[T] | first(), last() -> first, last | Optional[T], Optional[T] |
| same | Map[K, V] | length(), is_empty() -> length, is_empty | Int, Bool |
| same | Set[T] | length(), is_empty() -> length, is_empty | Int, Bool |
| `pkg/stdlib/bytes.ms` | Bytes | length(), is_empty() -> length, is_empty | Int, Bool |
| `pkg/stdlib/intrinsics.ms` | StringOperations / String | byte_length(), is_empty() -> byte_length, is_empty | Int, Bool |
| same | StringOperations / String | length(), scalar_length() -> length, scalar_length | Int, Int |
| `pkg/stdlib/optional.ms` | Optional[T] | is_some(), is_none() -> is_some, is_none | Bool, Bool |
| `pkg/stdlib/result.ms` | Result[T, E] | is_ok(), is_error() -> is_ok, is_error | Bool, Bool |
| `pkg/stdlib/intrinsics.ms` | FloatOperations / Float | is_nan(), is_finite() -> is_nan, is_finite | Bool, Bool |
| `pkg/stdlib/queues.ms` | Queue[T] | length(), is_empty(), peek() -> length, is_empty, peek | Int, Bool, Optional[T] |
| same | PriorityQueue[T] | length(), is_empty(), peek() -> length, is_empty, peek | Int, Bool, Optional[T] |
| `pkg/stdlib/time.ms` | Timestamp | unix_seconds(), nanoseconds() -> unix_seconds, nanoseconds | Int, Int |
| same | Duration | to_nanoseconds() -> nanoseconds | Int |
| same | Duration | to_microseconds() -> microseconds | Int |
| same | Duration | to_milliseconds() -> milliseconds | Int |
| same | Duration | to_seconds() -> seconds | Float |
| same | Duration | to_minutes() -> minutes | Float |
| same | Duration | to_hours() -> hours | Float |
| `pkg/stdlib/http.ms` | HttpExchange | headers(), method(), path(), query() -> headers, method, path, query | HttpHeaders, HttpMethod, String, String |
| same | ResponseBody | metadata() -> metadata | HttpResponseMetadata |
| same | ClientResponse | metadata() -> metadata | HttpResponseMetadata |
| `pkg/stdlib/fs.ms` | Directory | path() -> path | String |
| same | TemporaryDirectory | path() -> path | String |
| `pkg/stdlib/path.ms` | PathOperations | separator(), delimiter() -> separator, delimiter | String, String |
| `pkg/stdlib/websocket.ms` | WebSocket | subprotocol() -> subprotocol | String |
| `pkg/stdlib/log.ms` | Logger | level() -> level | LogLevel |
| `pkg/stdlib/net.ms` | IpAddress | family() -> family | IpFamily |
| same | DnsKind | text() -> text | String |
| same | IpFamily | text() -> text | String |
| `pkg/stdlib/http.ms` | HttpMethod | text() -> text | String |
| `pkg/stdlib/net.ms` | Connection | local_address(), peer_address() -> local_address, peer_address | String, String |
| same | Listener | address() -> address | String |
| same | DatagramSocket | address() -> address | String |
| `pkg/stdlib/http.ms` | HttpServer | address() -> address | String |
| `pkg/stdlib/sync.ms` | SynchronizedGuard[T] | get() -> value | T |

Naming decisions are part of this proposal:

- Keep length/is_empty, presence flags, first/last, non-consuming peek, metadata,
  address, path, level, family and text. Do not rename length to size or peek to
  first, and do not add aliases.
- Duration's six accessors are unit nouns. The first three retain signed integer
  division truncating toward zero; seconds/minutes/hours retain Float division,
  fractional values and precision. This approved unit projection migration is
  the exception to keeping conversion methods. Timestamp.nanoseconds remains
  the fractional second component; Duration.nanoseconds is the total span.
- SynchronizedGuard.value replaces get. set(value), wait(), notify_all() and
  close() remain methods. Synchronized.value remains a constructor input, not a
  public unguarded accessor.
- String.length and scalar_length retain their two approved names and identical
  Unicode-scalar units; neither becomes byte length or a grapheme count.
- DnsKind/IpFamily/HttpMethod.text are token reads; IpAddress.text() and Cidr.text()
  remain formatting methods, as do Timestamp.to_string() and universal toString().

Unify the **three existing** hardcoded Int properties, milliseconds, seconds and
minutes, under the same declared accessor mechanism in IntOperations. Keep their
current names, Int -> Duration checked scaling and overflow faults. They add no
new public names and are not part of the 56 method migrations. Do not add Int
hours/microseconds/nanoseconds or other unit constructors in this change.

Everything outside the table remains as it is. In particular retain actions,
mutation, I/O, parsing, formatting, conversions, clocks/OS queries, snapshot
creation, unwrap/unwrap_error, clone, freeze, keys, values, entries and join as
methods/functions. Path module free functions separator()/delimiter() remain
functions; this inventory covers PathOperations members only. Existing mutable
record fields, including HttpResponseMetadata fields and ClientResponse.head/body,
remain fields. BlockingQueue.length()/is_closed(), newly present on current main,
are unlisted and stay methods. No collection-prelude import migration is included.

### Explicit Error.message exclusion

Keep `pkg/stdlib/errors.ms`'s `fn message() -> String` interface operation,
implementations, bindings, bound function values, call sites and generated
signatures as methods. Preserve every user-defined Error implementation too.
At this baseline there are 34 standard implementations: ArchiveError,
BigIntError, BinaryError, CollectionError, CompressionError, CryptoError,
CsvError, EncodingError, MissingValue, TextError, FileSystemError, HtmlError,
HttpError, IoError, JsonError, LogError, NetworkError, NumberError, PathError,
CommandError, ProcessError, RandomError, RegexError, SseError, StringError,
SystemError, ExecutionError, StartError, TimeError, TlsError, TomlError,
UrlError, WebSocketError and YamlError. This includes source-owned implementations
in sse/toml/yaml, not just native entries in bindings.json. Case payload fields
named message remain ordinary payloads. This is an explicit invariant, not an
exception inferred from observational behavior.

## Compiler, native ABI and tooling design

### Keep one annotated tree and explicit member identity

Current architecture is syntax nodes with checker facts attached through Fact
([AST](https://github.com/manuscript-lang/manuscript/blob/main/pkg/syntax/ast.go), [checked facts](https://github.com/manuscript-lang/manuscript/blob/main/pkg/checker/model.go)).
Keep that architecture. Mark operation declarations in the existing Methods
collection as accessors (for example `Declaration.Accessor` while retaining the
ordinary callable body representation). Do not synthesize a call in source,
introduce a parallel accessor AST/IR, or desugar the read into a mutable field.
Retain source spans for the head, name, type and body; extend the shared visitor
and declaration consumers without losing any body traversal.

Currently Definition.Operations is `[]Param` (name/function type), and Method
has no member category ([types](https://github.com/manuscript-lang/manuscript/blob/main/pkg/checker/types.go)). Replace the
operation descriptor with a small checked descriptor carrying name, member kind
(method/accessor), callable implementation signature, and declaration identity.
An accessor's internal callable signature has no explicit parameters and result
T; its **member expression type is T**, while a method expression still has its
function type. Carry the kind on Method through substitution/native lookup,
implementation matching, generic evidence and editor queries. Reuse Info.Method
and its selected identity instead of maintaining a second accessor resolution
table on expression nodes. The descriptor is semantic metadata on the existing
tree, not a second executable representation.

Update operation equality/conformance, missing/extra/duplicate diagnostics,
public-surface validation, recursive type traversal and declaration loading to
retain kind and substituted result. Field equality/hashing and clone/storage
schemas still use fields/cases only; accessors are not stored data. An accessor
does not satisfy Equal/Hashable/Closeable method requirements merely by name.
Visibility and local implementation selection remain those of the selected
Method, including module ownership and inherited receiver bounds.

### Resolve reads before callable fast paths

Member inference in [expressions.go](https://github.com/manuscript-lang/manuscript/blob/main/pkg/checker/expressions.go) currently
returns method function types, with separate Int unit handling. Resolve a member
once, attach its kind, and project the accessor's result type for reads. Check
assignment against the resolved kind, with a dedicated read-only diagnostic.
Remove the special Int-unit branch after declarations/bindings represent it.

[nativeCallable](https://github.com/manuscript-lang/manuscript/blob/main/pkg/checker/native_members.go) is a critical second path:
it can install a callable Info without ordinary inferMember. It must use the
same member resolver/kind and must never treat an accessor as a method callable
or specialize it as one. Old `xs.length()` should reach the accessor diagnostic,
not native method inference. Generic bounds and explicit interface views must
retain accessor identity even when runtime dispatch is necessary.

An accessor returning a function is still a value read. If its declared result
is callable, `x.operation(args)` reads that function and calls it under ordinary
function rules; it does not call the accessor with arguments. Consequently an
old-call diagnostic is conditional on a noncallable accessor result, not a
blanket syntax ban. All same-name migrated standard getters return noncallable
types; guard.get is separately renamed. Do not auto-specialize an accessor with
`x.member[T]`; receiver specialization remains available normally.

### Effects and callable graphs include reads

[effectSummaries](https://github.com/manuscript-lang/manuscript/blob/main/pkg/checker/effects.go) currently identifies record field
reads at KindMember and most callable effects at KindCall. Simply changing
KindMember lowering would drop source getter effects and misclassify native
ones. At a resolved accessor read, add the same source implementation edge or
native conservative effect classification as an equivalent operation invocation.
Use an operation-level helper taking the resolved member and name; do not assume
the name lives at `expression.Left.Text`, as scanMethodCall currently does.
Add at least `read` for observational native reads; retain broader existing
conservative effects (for example HttpServer) and `unknown` for unresolved
interface/generic implementations. Guard.value must retain get's read category
rather than falling into the renamed operation's write case. Source bodies
propagate their actual write/external/unknown effects. Do not narrow unrelated
effect classifications in this migration.

Accessor execution edges also belong in source reachability, inspection/call
diagrams and [recursive-cycle detection](https://github.com/manuscript-lang/manuscript/blob/main/pkg/lower/lower_recursion.go).
Mutually recursive accessors and method/accessor cycles must participate in the
same SCC/depth accounting as calls. A bound method reference alone remains a
value construction; an accessor member expression executes. Update all consumers
that currently use KindCall as a proxy for execution. Reuse checked resolution
and indexed descriptors; do not repeatedly rescan declarations per read.

In particular, triedScan in [lower_try.go](https://github.com/manuscript-lang/manuscript/blob/main/pkg/lower/lower_try.go) currently
visits only the receiver of KindMember without marking an effect. An accessor
read must mark an execution barrier there. In `consume(x.property, try fail())`,
hoisting the failing try must not skip x.property's code, validation, cancellation
or fault. Preserve the existing transparent behavior for ordinary field/method
references where applicable. Add an observable ordering regression, not only an
effect-summary assertion.

### Native declarations and runtime dispatch

Public signatures and member kind remain owned by `.ms` source. Update standard
loading, exact pinned-source authorization and ABI conformance tests to compare
member kind as well as receiver, arguments, result, generics and bounds. Preserve
the lightweight frontend/nativeabi dependency boundary.

Keep existing internal native operation identities where possible. For example,
Duration.seconds binds `time/duration_seconds`; public to_seconds disappears.
Rename the public key in [ReceiverBindings](https://github.com/manuscript-lang/manuscript/blob/main/internal/nativeabi/receivers.go),
not the underlying algorithm. Remove accessor names from callable native member
factories and method caches. bindings.json remains an identity/authorization
manifest, not a duplicate public signature/accessor schema. Runtime ABI metadata
must expose member category for conformance; a method-only native implementation
cannot silently satisfy a get declaration. Update Native receiver metadata,
Library/LibraryMethods conformance and intrinsic binding coverage together.

Use one runtime read entry for genuinely dynamic interface/generic accesses,
conceptually `ReadAccessor(ctx, receiver, contract, name, scope)`. Resolve only
accessor entries. Native handles provide a receiver-only read entry, and source
implementation registration supplies a receiver-only accessor thunk alongside
existing method entries. A read must never fall back to `Bind(...).Body`,
`Native.Operation(name)`, NewFunction or Invoke. Existing methods continue using
their existing callable mechanism.

The dynamic resolver reuses existing implementation matching and TypeScope.
Unwrap View while retaining its concrete receiver and **its scope**, substitute
receiver type arguments and their scopes, and honor local implementation
visibility. Include member kind in registry/cache/site identity; retain contract,
module, receiver and generic argument scopes. A cache stores a dispatch target,
never a receiver or result. Source generic specialization may retain an unbound
thunk per specialization; it must not allocate a receiver-bound Function per
read. Shared runtime check/body helpers serve both the static path and dynamic
read entries. No public legacy-method aliases are retained.

### Lowering and representations

Select an accessor lowering plan from checked facts **before** lowering operands,
then emit the receiver exactly once using existing ordered capture machinery.
Eligibility probing must not emit and discard AST/source markers. Extend
memberValue, nativeType/scalar lowering, source direct-method planning, alternative
use analysis, ordered `try` handling and source registration as needed. Continue
constructing Go AST directly; no generated-Go string parsing or duplicate IR.

- A concrete source accessor lowers to its receiver-only direct Go function
  where current source method eligibility applies. Generic/unresolved interface
  access uses the runtime read entry with preserved evidence.
- A statically resolved native accessor lowers to a typed receiver-only operation
  or helper. Execution context is an implicit runtime input where checks need it;
  there are no explicit source arguments, label arrays, `[]Argument`/`[]Value`
  call preparation, bound Function, Invoke, Bind or CallNative for this read.
- Helpers return int64/float64/bool/string for scalar results; integrate these
  types with existing typed locals and parameters. Box only at an existing Value
  boundary. Do not route Bool/Float results through new boxed temporaries.
- Preserve typed Option.Some/Result.Failed when a receiver already has that
  representation. Extend the narrowly scoped alternative-use classifier so
  presence-flag reads, together with currently safe match uses, do not force
  boxing an otherwise typed immutable local. Keep var/capture/escape restrictions.
  For boxed receivers inspect Alternative.Tag; do not unpack or allocate payloads
  to answer a flag. Do not introduce pointer Option storage or change tags.
- Preserve Optional-producing first/last/peek representation at existing ABI
  boundaries. Reuse existing match-oriented typed lowering where applicable;
  do not expand into collection storage, generic specialization or callback ABI
  redesign. No broad backend optimization belongs in this feature.

Private native fields may require exported runtime helpers. Those helpers read
the authoritative handle and retain checks; they must not expose mutable Go
storage as a public Manuscript field. ClientResponse.metadata can use the current
head field getter directly with the required native checkpoints, not a second
record slot.

### Tooling and documentation

Update strict/partial parser recovery, formatting/idempotence, contextual get
highlighting in the shared VS Code grammar, checked completion, hover, signature
help, navigation, references and rename. Accessors appear as read-only properties
with value types and insert no `()` snippet. Existing methods still insert call
syntax. Navigate workspace -> standard accessor -> signature types/imports using
the immutable standard documents. Invalid/incomplete accessor declarations must
not erase neighboring declarations or shift LF/CRLF/Unicode positions.

Inspection must distinguish storage reads, accessor executions and callable
references. Expose accessor targets/effects to diagrams and source tools without
pretending each member is a source KindCall. Preserve source line mapping and
existing debugger tests; do not redesign debugger value rendering or make it
evaluate getters while inspecting a value. Reading a property in an explicit
source expression is different from debugger inspection of stored fields.

Generate declaration excerpts as `get name -> Type`, preserving comments. Add
accessor member classification to documentation/inspection schemas deliberately:
document it and update all repository consumers. For API JSON, introduce an
additive `accessors` array and member kind `accessor`, retain existing fields and
operations arrays for their original categories, and bump the schema version for
the changed interpretation of migrated entries. Do not serialize accessors as
mutable fields or pretend their public type is `fn()->T` for compatibility.
Regenerate references/downloads through make docs after integration with main.
Put shipped exact rules in core-language grammar/contracts/expression rules and
link tutorials to them. This proposal stays labelled pending until approval and
implementation; do not teach the proposed API as shipped during design review.

## Compatibility and call-site migration

This is a breaking source API change. Ship compiler, standard source, runtime,
editor metadata and generated references together under a new implementation pin.
Do not support both getter() and getter publicly, add implicit auto-invocation,
or introduce a compatibility flag. Retain old names only as diagnostic migration
data and intentional rejection cases, not exported members or dispatch aliases.

Suggested diagnostics follow `<cause>; <fix>` and carry exact source edits when
safe:

- `length is a read-only accessor, not a method; write xs.length without ()`
- `to_seconds was replaced by the seconds accessor; write span.seconds`
- `get was replaced by the value accessor on SynchronizedGuard; write guard.value`
- `cannot assign to read-only accessor value; use guard.set(value: ...) to replace the guarded value`
- `length must implement an accessor contract; declare get length -> Int`

Use the user's actual receiver expression in fixes. Removing `()` is automatic
only for a resolved migrated getter with no arguments and a noncallable result.
Preserve comments and avoid dropping argument evaluation. Unknown-name hints for
old Duration/guard names are keyed by nominal receiver, not global spellings.
General accessor assignment diagnostics must not invent a setter.

Method-reference migration needs separate treatment:

```manuscript
# Before: stores a callable bound to the current receiver.
let count = items.length

# After: reads and stores the current Int immediately.
let count = items.length

# After, when a callable is needed: captures this receiver and reads on invocation.
let receiver = items
let count_later: fn() -> Int = fn() -> Int: receiver.length
```

When the old reference is `make_items().length`, first bind
`let receiver = make_items()` at the original reference site, then create the
closure. Putting make_items() inside the closure would change receiver evaluation
time/count. Manuscript closures snapshot bindings and retain reference aliases,
so this preserves the bound receiver while allowing live reads on later calls.
It does not keep a guard/resource open. Diagnose expected-function contexts with
an explicit closure remedy. Unannotated references can change inferred type and
timing silently; audit their uses, stored fields, returns and higher-order
arguments rather than relying solely on compile errors.

After approval, perform migration by checked receiver/member identity, not a
repository-wide replacement of `.get`, `.text`, `.path` or `.length`. First record
all resolved calls and references against the old declarations, including source
ranges and contexts; then rewrite against the inventory. A temporary migration
analysis can consume the existing annotated tree; it need not become a new CLI.
Rewrite calls to reads, inherited interface implementations to get, and callable
references to explicit receiver-capturing closures where callable intent remains.
Do not rewrite unrelated user methods with the same names. Migrated standard
interfaces require source adapter/mock implementations to migrate too; user
interfaces outside the inventory are not automatically redesigned.

Audit all consumers: pkg/stdlib source modules; Go embedded Manuscript test and
benchmark strings; parser/checker/lower/runtime/ABI/tooling expectations;
tests/e2e including projects and stdlib fixtures; tests/examples; examples;
ms-bench; scripts/bench-*; extension tests; declaration exports and documentation
snippets; generated API references, downloads, highlighting and search artifacts.
Runtime fault remedies mentioning is_some()/is_ok()/scalar_length() and stdlib
doc comments about length() must use current syntax. Preserve historical
independent emitted-Go baselines such as lower/testdata/go-ast deliberately:
keep historical input/output paired and document any harness-only adaptation,
rather than overwriting independent evidence with newly generated output.

Search again after regeneration for all migrated declaration spellings and
bound/native member aliases. Classify residual matches as unrelated methods,
intentional rejection diagnostics or documented historical baselines. A grep
count is a discovery aid, not proof of correct typed migration. In particular
Error.message() calls/references and all retained snapshot/conversion methods
must survive this audit. Rebase only on main; PR497 has now merged, so reconcile
the prelude from main and regenerate combined references without adopting a
separate collection-prelude branch during this work.

## Performance evidence and acceptance

The original audited 18 candidates comprised 5 direct helpers, 6 hoisted
NativeCall paths and 7 full-binding paths. The six hoisted candidates included
List.first/last, Map/Set.is_empty, Bytes.is_empty and String.is_empty. The seven
full-binding candidates are Bytes.length, Optional.is_some/is_none,
Result.is_ok/is_error and Float.is_nan/is_finite.

String.length and String.scalar_length were two additional candidates, already
included in the approved migration. At the design baseline, source inspection
predicted 6 direct (List/Map/Set.length, List.is_empty, String.byte_length and
String.length), 7 hoisted (List.first/last, Map/Set.is_empty, Bytes.is_empty,
String.is_empty and String.scalar_length), and the same 7 full-binding paths.
There is no demonstrated discrepancy with the original audit. This corrects the
evidence inventory, not the feature scope. Verify all 20 emitted expressions and
use actual current-main output as the benchmark baseline. These predictions are
historical source inspection, not executed emission results or timing measurements. The
remaining service/time inventory is outside these 20.

Required emitted-Go shapes below are acceptance sketches, not generated output.
Helper names are illustrative; they must return the stated typed value and
retain the path-specific checkpoints described above. Context and fixed type
evidence are permitted implicit inputs. No accessor-result caching is implied.

```go
// make_items().length: receiver once, int64 result, authoritative handle.
r := makeItems(ctx)
n := rt.ListLengthRead(ctx, r) // int64; not boxed CollectionLength(...).(int64)

// bytes.length: fixed native operation, no Function or Invoke.
count := rt.BytesLengthRead(ctx, data) // int64

// Optional flags: keep an existing typed Option and read the tag only.
o := sourceOptional(ctx) // rt.Option[int64]
present := rt.OptionalSomeRead(ctx, o.Some) // bool; retains native checkpoints

// Already-boxed Optional: no payload extraction/allocation or reboxing.
present = rt.OptionalSomeRead(ctx, a.Tag == "some")

// Float: float64 in, bool out; preserve NaN and infinity behavior.
finite := rt.FloatFiniteRead(ctx, f) // bool

// Duration unit projections: preserve division and result type.
seconds := rt.DurationSecondsRead(ctx, span) // float64, same division as today

// Concrete source accessor: receiver-only direct target.
n = accessorLength(ctx, buffer) // int64

// Interface/generic case: resolve using contract and lexical evidence.
v := rt.ReadAccessor(ctx, view, contractKey, "length", scope)
```

For each statically resolved accessor assert absence of NativeMemberResult,
Bind/Invoke, NewFunction, BindNativeCall/CallNative, and prepared argument slices
for that read. Assert the same no-bound-Function rule for the dynamic accessor
entry itself. Whole programs can contain these for unrelated methods. A native
helper may not hide those factories internally. In the typed Optional example,
evaluate the receiver before admission checks, inspect no payload, and retain
the required delivery check; the helper is not permission to reorder faults.

After approval, extend the existing bench-lowering approach with focused accessor
workloads. Do not run or report a hypothetical accessor implementation now.

| Workload | Required controls and observation |
| --- | --- |
| Each of the 20 candidates, separately | Same receiver/data and consumed result; baseline current method lowering vs new accessor lowering; compare direct, hoisted and bound groups separately. |
| Mixed collection reads | Mutation between reads; typed primitive and boxed List storage; first/last empty/present; stable result checksum. |
| Presence/classification | some/none and ok/error; typed and boxed/captured receivers; Float finite/NaN/+Inf/-Inf and signed zero; avoid compile-time constants. |
| Unicode lengths | ASCII and non-ASCII; repeated identical text and alternating strings; retain current internal cache behavior and scalar units. |
| Source/interface/generic reads | Concrete impl, explicit view, generic bound, and two module-local implementations; include an explicit closure replacing an old bound getter reference. |
| Guard/logger/metadata | Uncontended and coordinated contended reads, closed guards, metadata aliases/head replacement; report dispatch separately from mutex cost. |

Retain generated Go and escape analysis for both revisions, verify identical
observable results, then benchmark native loops without compilation/startup in
the timed region. Use the same pinned Go, build type, CPU and runtime settings,
multiple samples, benchmem and a statistical comparison. Include a handwritten
typed helper control with equivalent cancellation/fault/alias checks, plus an
unchanged-method control to detect harness drift. Record ns/op, B/op and
allocs/op; do not claim all candidates improve because seven remove binding.
Do not remove language guarantees from the control to manufacture parity.
Measure check/emit/build separately on N/2N/4N accessor-heavy inputs to detect
lookup or graph regressions. A semantic pass is mandatory even if timing is noisy.

## Required tests and release checks

Tests must exercise reads, not just declarations:

- Parser: source impl, interface and native forms; inline suites, inherited
  generic types and function-valued results; rejection of parentheses, parameters,
  defaults, own type parameters, top-level get and unauthorized empty bodies;
  contextual identifiers; strict/partial recovery, positions, formatter roundtrip
  and idempotence. Extend parser fuzz seeds at the new declaration boundaries.
- Checker: get-vs-fn conformance in both directions; missing/extra/duplicate
  accessors; field collisions; explicit view ambiguity; generic substitution,
  bounds and visibility; public result types; nativeCallable bypass regressions;
  assignment rejection on concrete/native/interface/generic receivers; callable
  results; old-call and rename diagnostic fixes; source-only AnalyzeOnly.
- Effects/graphs: field vs method reference vs accessor read; source getters
  performing writes/calls; native read effects; guard.value classified as read;
  unknown dynamic reads; reachability; self-recursive, mutually recursive and
  mixed accessor/method cycles with sampled depth/cancellation and fault frames.
- Native/ABI: compare every one of the 56 declarations plus the three existing
  Int properties by kind, receiver and result; mismatched method/accessor ABI
  deliberately fails. Cover lean/full bundles, standard source exports, runtime
  source embedding, pin invalidation and all build modes.
- Execution: receiver side effects exactly once; left-to-right order around
  calls/defaults/try/match; skipped short-circuit reads; repeated reads after
  alias mutation; Optional none and some(none); mutable element/header/metadata
  identity; ClientResponse head replacement; Unicode lengths; Float classifiers;
  negative Duration truncation/fractions/extremes and Int scaling overflow.
- Resources/concurrency: stale/closed/temporarily released guard reads fault;
  no stale payload after another acquisition; cancellation before/during/delivery
  of a contended native read; live Logger.level after set_level; existing
  post-close metadata/address/path/subprotocol availability. Coordinate races
  rather than relying on sleeps. Re-run existing guard wait/notify/alias-close
  and HTTP/socket lifetime regressions; add no new lock or I/O behavior.
- Tooling: value-type property completion without parentheses, hover/docs,
  definition/references/rename, expected-function remedies, standard virtual
  navigation, incomplete snapshots, accessor inspection targets/effects and JSON
  schema consumers. Source mapping/fault lines and existing native debugger cases
  must pass, without expanding debugger scope.

**Error.message non-regression is a release blocker.** Assert the Error operation
and every discovered standard Error implementation remain method-kind, with no
accessor metadata/binding. Execute concrete and explicit Error-view calls,
generic `T: Error` calls, stored `let describe: fn() -> String = err.message`
followed by describe(), and a user-defined implementation. Cover native and
source-owned standard errors and verbatim Failed text. The declaration inventory
test must discover implementations, not freeze the count 34 and miss future
ones. Preserve message() in generated docs, completion and navigation. A bare
err.message must remain callable and must not immediately execute the body.
Keep conversions, unwrap/clone/freeze and snapshot method controls callable too.

Use current repository targets after implementation: affected Go package tests,
make repo-check, make stdlib-check, called make stdlib-test and make e2e cases,
make examples-check, make docs followed by docs-check/book-check, and relevant
race/fuzz checks. Run make verify and the applicable verify-full gates before
publication; standalone distribution tests must cover copied binaries, lean/full
runtime and supported targets. Regeneration follows integration with main.
Report unavailable platform/native checks explicitly. For this design-only edit,
validate inventory, local links, scope and patch whitespace; no compiler/runtime
test run would establish the proposed behavior.

## Stages, ownership and approval gate

| Stage | Owner | Reviewable exit condition |
| --- | --- | --- |
| 0: design (this stage) | Design author; parent owns coordination | Save this document and return its full text/path. Parent appoints a separate skeptical reviewer; address their findings in the document. No implementation or PR publication. |
| Gate | Independent reviewer, relayed by parent | Explicit approval of syntax, exact inventory, effects/evidence, runtime checkpoints and bounded performance plan. No self-approval or inference from silence. |
| 1: checked member model | Implementation owner, language/compiler review | get parsing, member kind/evidence, checking, effects/graphs and native ABI validation; source/interface/generic acceptance and rejection tests. Keep a buildable integrated worktree. |
| 2: execution/lowering | Same implementation owner, runtime/compiler review | Receiver-only static helpers and dynamic read entries; TypeScope, lifetime, cancellation/fault/representation tests; emitted-Go assertions. No generic backend redesign. |
| 3: coordinated migration | Implementation owner, tooling/docs review | All 56 getters and three existing Int properties use the mechanism; all typed calls/references/adapters migrated; Error exclusion tests; generated docs/editor/schema changes. |
| 4: verification and delivery | Implementation owner; parent coordinates final review/publication | Focused before/after evidence and applicable repository/native gates pass; review final integrated diff and compatibility notes before the separately authorized publication step. |

These are implementation checkpoints, not independently releasable partial APIs.
Keep compiler, library, runtime and consumers coherent at the release boundary.
Any semantic gap found during implementation must be fixed within this design or
returned to review before broadening scope. Recover by reverting the coherent
feature/migration set, not by retaining half of a dual API. Do not mix rollback
with unrelated PR497/debugger/performance changes.

All naming choices and the migration boundary are resolved above. The independent
design approval gate is satisfied. Implementation remains within this approved
scope; draft PR publication is authorized and merge awaits parent clearance.
