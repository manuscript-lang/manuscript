# Opaque types

## Summary

- Problem: a value that a human-owned module hands out (an approval, a secret, a validated input) can be re-minted or duplicated by agent code outside that module. Construction, implicit copy, `.clone()`, collection copies, `json.parse`, and `f"{value}"` all work on any exported record, so "use once, for this entity" is advisory.
- Change: one rule. An exported record with a hidden field that has no default is **opaque**: outside its module it cannot be built, read, written, destructured, or cloned; everywhere it is a moved, never-copied value with no derived `Clonable`, `Equal`, or `Hashable`, as interface values are today. Decoding, encoding, interpolation, and `to_string()` reject a type that holds an opaque type; how a generic wrapper that renders a bare type variable is stopped is the one open decision.
- Prerequisite: collection methods that copy elements (`take`, `slice`, `reversed`, `concat`, `filter`, `find`) accept non-`Clonable` elements today; `xs.concat(xs)` on a list of one `Closeable` closes it three times. They move under `T: Clonable` interfaces first.
- Cost: hidden-field derivation, an opaque check, and a `holds_opaque` property in `crates/ms-check`, one line in the ownership classifier, the check on the rendering and decoding entry points, one `ms review` report. No syntax, no runtime change.
- Decision requested: approve the rule and the prerequisite PR, and choose how bare-`T` rendering is handled (Open questions).

## Status

- Proposal, 2026-10-28, checked against main `23129640`. Accepted and leaking examples are pasted `ms check` output; rejections under the new rule are marked proposed.
- Direction (Chinmay, 2026-10-28): "let's find the crux of the problem and propose point solution for that"; "iterate a few times to simplify and ensure it truly increases confidence in agent generated code, do 3 consecutive runs with skeptic review".
- Skeptic review round 1 (`architecture/opaque-types-review-1.md`, project files): REVISE. Resolved here: collection copies are a prerequisite; opacity reuses the `Resource` class and the computed `Clonable` property instead of a tag and an `impl Clonable` opt-in; generics are closed by bounds at definition; `RelPath`/`HttpUrl`, #1537, factory functions, and the stdlib adoption PR are dropped; trust boundary and do-nothing restated.
- Skeptic review round 2 (`opaque-types-review-2.md`): REVISE. Resolved here: opaque values are classed `Move`, not `Resource`, so no close path is touched; the interpolation bound is narrowed to types that hold an opaque type plus bare type variables (zero such sites in `stdlib/`); the defaulted-marker hole is stated and reported by `ms review`; `Equal` and `Hashable` are never derived; alternatives cannot be opaque; line references refreshed.
- Skeptic review round 3 (`opaque-types-review-3.md`): REVISE with two items, "then approvable as a point solution"; probes with an interface value confirmed drop, `List`/`Optional` in scope, `with`, `Set`, and `Equal` behave as claimed. Resolved here: `to_string()` added to the rendering rule; the three fixtures that render a bare `T` are named and the decision is put to the owner; un-exports, the partial-move paragraph, and the #1422 reference are cut; the `decode` entry points and the private-type check are cited correctly.
- Supersedes `resources-for-logic.md` (removed). Extends the project-file proposal `private-field-types.md`: its derived hiding stands for defaulted hidden fields; a hidden field without a default is what makes a type opaque.

## Problem

`gate.ms` mints `Approved[Delete]` only from a signed request and takes it apart once in `spend`. Agent-written `forge.ms` defeats every part of that with no diagnostic (`Checked forge.ms`):

```manuscript
from "./gate.ms" import Approved, Delete, spend
from "@std/json.ms" import parse

def forge() -> Approved[Delete]: Approved[Delete](entity: "u2", nonce: "x")

def decode() -> Approved[Delete]:
    return parse[Approved[Delete]]("{\"entity\":\"u2\",\"nonce\":\"x\"}").get(forge())

def twice(a: Approved[Delete]) -> Int:
    let first = spend(a.clone(), "u2").get("")
    let second = spend(a, "u2").get("")
    return first.length() + second.length()

export def main() -> Int:
    let a = forge()
    let copy = a.clone()
    let line = f"{a}"
    return twice(copy) + twice(decode()) + line.length() + a.nonce.length()
```

- Without `.clone()` on line 10 the checker rejects the second `spend` ("`a` is moved here but used again at 11:24; a value has one owner"). Ownership is the right mechanism; the escapes around it are the problem.
- Two more escapes, verified: a generic `def show[T](v: T) -> String: f"{v}"` renders anything, and so does `a.to_string()`, which every value has (`stdlib/intrinsics.ms:6-8`); `[h].concat([h])`, `take`, `reversed`, `filter`, `find`, and `List.clone()` duplicate elements of any class, including `Closeable` (review round 1 ran one `close` three times).
- A record of scalars copies implicitly (`Money(cents: 5)` passed twice checks clean), so it has no owner.
- The stdlib has the same problem with itself: `Entry`, `Inbox`, `Open` (`stdlib/tasks.ms:287`, `processes.ms:106`, `:307`) are exported only because a public record holds them, and are documented "Internal state". Un-exporting them is a follow-up, not part of this change.
- Non-goals: must-consume (dropping an approval is allowed), typestate tooling, import restriction, who may edit a module, proving value facts.

## Design

Rule: an exported record with a hidden field that has no default is opaque. A hidden field is one whose type is private to the declaring module (`private-field-types`: the record-field check that today reports "public signature exposes private type", `contracts.rs:1008`, accepts the field instead and marks it hidden). A hidden field with a default keeps that proposal's behavior (constructible, field hidden), which is what `TaskGroup` and `ProcessGroup` need and what their 39 call sites use.

Outside the declaring file an opaque type:

- cannot be constructed, and no field can be read, written, or named in a pattern, including public-typed fields. `impl` blocks elsewhere follow the same rule.
- cannot be used through an `impl` block in another file either; the field ban is by declaring file.

Everywhere, including inside the module:

- the computed properties `Clonable`, `Equal`, and `Hashable` (`contracts.rs:613`, `:758`) are false for an opaque type and for any type holding one, in every file; the module may `impl Equal` or `Hashable`, and `holds_resource` (`contracts.rs:673`, the set-element and map-key gate) gains the same `holds_opaque` test.
- the value is classed at least `Move` in `crates/ms-check/src/ownership/classify.rs` (`nominal`, line 90, today starts the fold at `Copy`): it moves at its last use and never copies implicitly, even when every other field is a scalar. `Move` without `Clonable` is what an interface value is today, so no close path is involved: an unspent approval is dropped silently, and `with` rejects it as not `Closeable`. (Round 2 showed `Resource` would mean must-close and fail in `ms-lower/src/with.rs:380`.)
- every rendering and decoding path rejects a type that holds an opaque type (`holds_opaque`, transitive through `Optional`, `Result`, `List`, records, alternatives): string interpolation, the intrinsic `to_string()` (`stdlib/intrinsics.ms:6-8`), `parse[T]` (`stdlib/json.ms:174`), `stringify[T]` (`:258`), and the exported entry points of the private decoders, `cli.command[T]` (`cli.ms:285`, which calls `decode` at `:298`) and the channel receive paths in `processes.ms` (`:236`, `:285`). Interfaces, `Closeable` records, and everything else render as today.
- a generic that renders a bare type variable (`def show[T](v: T) -> String: f"{v}"` or `v.to_string()`) is the one remaining path, since `T` may be instantiated with an opaque type. The language documents that rendering: `stdlib/intrinsics.ms:6` ("including unconstrained type parameters"), and three accept fixtures cover it (`tests/conformance/fixtures/e2e/accept/to-string.ms:29`, `to-string-fmt.ms:29`, `tests/e2e/testdata/accept/to-string.ms:26`). `stdlib/` has no such site. The two ways to close it are in Open questions; either keeps the guarantee.
- inside the module, `spend` consumes its parameter because the value moved into the call; destructuring semantics are unchanged (partial move out of a record is out of scope).

The marker is implicit, and the proposal says so rather than adding syntax: adding `= Seal()` to the hidden field, or exporting `Seal`, makes the type constructible again with no diagnostic. `ms review` reports "`Approved` became constructible outside `gate.ms`" for either edit, the fixture suite asserts the defaulted variant is constructible, and the glossary entry says it. An exported alternative cannot carry a hidden field, so it cannot be opaque; wrap it in a record.

Prerequisite, independent of this proposal: `List`, `Map`, and `Set` methods that return copies of elements (`clone`, `take`, `slice`, `reversed`, `concat`, `filter`, `find`, `find_last`, `min`-style) move into `interface ...[T: Clonable]` blocks like `ListExtremes` (`stdlib/collections.ms:568`). Methods that borrow (`get`, `first`, iteration) are unchanged. This is a `.ms`-only fix for an existing soundness bug with `Closeable` elements.

```manuscript
# gate.ms: proposed; today line 5 fails "public signature exposes private type Seal"
type Seal:

export type Delete:

export type Approved[T]:
    entity: String
    nonce: String
    seal: Seal

export def approve(request: SignedRequest) -> Result[Approved[Delete], GateError]:
    let {entity, nonce, signature} = request
    if signature != f"sig({entity},{nonce})": return error(BadSignature)
    return ok(Approved[Delete](entity: entity, nonce: nonce, seal: Seal()))

export def spend(approval: Approved[Delete], entity: String) -> Result[String, GateError]:
    let {entity: approved, nonce} = approval
    if approved != entity: return error(WrongEntity)
    return ok(nonce)
```

Proposed diagnostics for `forge.ms`:

```text
forge.ms:4:34: type: Approved[Delete] is opaque outside gate.ms; build it with approve
forge.ms:7:12: type: parse cannot build Approved[Delete]; it is opaque outside gate.ms
forge.ms:10:23: type: unknown member clone on Approved[Delete]; it is opaque outside gate.ms
forge.ms:17:16: type: Approved[Delete] is opaque and cannot be rendered (same for a.to_string())
forge.ms:18:60: type: field nonce of Approved[Delete] is hidden outside gate.ms
```

What holds afterwards, by the existing move checker: every `Approved[Delete]` came from `approve`, is spent at most once, names the entity the signature named, and is never rendered or encoded. The guarantee is relative to `gate.ms` as written; who may change `gate.ms` is a repository question (CODEOWNERS), not a checker one, and `ms review` already ranks signature changes to it.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/collections.ms` (prerequisite) | element-copying methods under `T: Clonable` interfaces | reject: `concat` on a list of `Closeable`; accept on `Int` |
| `crates/ms-check/src/contracts.rs` | fields skip `public`; hidden-field derivation; `holds_opaque`; opaque types fail `Clonable`/`Equal`/`Hashable`; set-element and map-key gate | accept: exported record with private-typed field; reject: `Set[Approved]` |
| `crates/ms-check` records, members, patterns | opaque check by declaring file | one reject fixture per operation; accept inside the module |
| `crates/ms-check/src/ownership/classify.rs` | opaque record folds from `Move` | reject: scalar-only token used twice; accept: `spend` consumes, unspent approval dropped, `List[Approved]` and `Optional[Approved]` in scope, `with` on it rejected |
| `crates/ms-check` interpolation, `to_string`, `parse`, `stringify`, `command`, channel receive | reject an operand that `holds_opaque`; bare `T` per the open question | reject: `f"{approval}"`, `approval.to_string()`, `f"{some(approval)}"`, `show(approval)`; accept: `f"{err}"` with `err: Error`, `f"{handle}"` on a `Closeable`, `Map[Approved, Int]` rejected |
| `crates/ms-tooling` `ms review` | report an exported record becoming constructible outside its module | tooling test: default added to hidden field; hidden type exported |
| lowering, MIR, codegen, `ms-rt`, ABI, parser, formatter, lint, LSP | unchanged (`Move` values take no close path) | existing |
| `documentation/core-language/types/records.md`, `modules/boundaries.md`, `glossary.md` | hidden field, opaque, consuming destructure | `make docs`, repo-check |
| platform parity | checker and `.ms` only | CI matrix, nothing gated |

## Alternatives

- Do nothing: `forge.ms` and the collection bug stay accepted; the stdlib keeps exporting internal state.
- A lint ("construct, parse, clone, or interpolate a record declared in another module"): catches `forge.ms` as written and is the honest baseline. It cannot see through generics, collection methods, or implicit copies, which is exactly where the review found the leaks; the rule's marginal value is that the ownership checker tracks those already. No measurement shows agents forge approvals; the stdlib's own "Internal state" exports show the discipline fails without the compiler.
- `private-field-types` alone: closes field access; defaults, `parse`, `.clone()`, copies, and interpolation stay open.
- A `structural` tag in `bindings.json` (first draft): a second mechanism with no rule for generic instantiation. `holds_opaque` is one transitive property like `holds_resource`, and the bound closes generics at definition.
- `T: Clonable` on every interpolation (second draft): breaks `f"{err}"` for every interface value, since contracts are never `Clonable`. Narrowed to opaque-holding types; bare variables are the open question.
- Classing opaque values `Resource` (second draft): `Resource` means must-close, and a record with no `close` fails in lowering. `Move` is the right class.
- An `opaque` modifier: same semantics, new grammar, formatter, LSP, docs. "No default on a private field" already says only the module can supply it.
- Drawbacks: a field like `seal: Seal` is the marker, not self-explaining, and one added default removes the guarantee silently (`ms review` reports it, which is advisory; the guarantee rests on review plus CODEOWNERS); collection methods gain a bound that may break code holding resources in lists, which is the bug.

## Staging and verification

- PR 1, prerequisite: collection bounds and fixtures. Gate: `make verify-full`, since stdlib and e2e code may hold resources in lists.
- PR 2: hidden fields, opaque check, classifier line, `holds_opaque` on the rendering and decoding paths, the bare-`T` decision, the `ms review` report, docs, `forge.ms` and `gate.ms` as conformance reject and accept cases, the defaulted-marker fixture. Gate: `make verify`.
- Evidence: the fixtures; no benchmark claimed. The claim is narrow: every `Approved` came from `approve` and was spent at most once, relative to `gate.ms` as written.

## Open questions

- Bare type variable in a rendering position, two options:
  - Infer a per-parameter "rendered" flag while checking a generic body (interpolation, `to_string`, `parse`, `stringify` of a bare `T`, or passing it to a flagged parameter), as `crates/ms-check/src/effects.rs` infers effects, and reject a call that instantiates a flagged parameter with a type that `holds_opaque`. Recommended: no language change, the three fixtures stay, the leak closes at the call. Cost: one inferred flag with the same fixpoint as effects.
  - Require `T: Clonable` to render a bare `T`: the existing bound mechanism, but it is a language change that re-bounds the three fixtures and contradicts `intrinsics.ms:6`.
- The implicit marker: accept it with the `ms review` report (recommended; no syntax) or add an explicit marker later if the report proves insufficient.
