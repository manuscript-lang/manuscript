# Opaque types

## Summary

- Problem: a value that a human-owned module hands out (an approval, a secret, a validated input) can be re-minted or duplicated by agent code outside that module. Construction, implicit copy, `.clone()`, collection copies, `json.parse`, and `f"{value}"` all work on any exported record, so "use once, for this entity" is advisory.
- Change: one rule. An exported record with a hidden field that has no default is **opaque**: outside its module it cannot be built, read, written, destructured, or cloned; everywhere it is a moved, never-copied value with no derived `Clonable`, `Equal`, or `Hashable`, as interface values are today. Decoding, encoding, and interpolation reject a type that holds an opaque type, and a generic wrapper that renders a bare type variable needs `T: Clonable`.
- Prerequisite: collection methods that copy elements (`take`, `slice`, `reversed`, `concat`, `filter`, `find`) accept non-`Clonable` elements today; `xs.concat(xs)` on a list of one `Closeable` closes it three times. They move under `T: Clonable` interfaces first.
- Cost: hidden-field derivation, an opaque check, and a `holds_opaque` property in `crates/ms-check`, one line in the ownership classifier, a check on four stdlib builders and interpolation, one `ms review` report. No syntax, no runtime change.
- Decision requested: approve the rule, the `T: Clonable` requirement for rendering a bare type variable, and the prerequisite PR.

## Status

- Proposal, 2026-10-28, checked against main `23129640`. Accepted and leaking examples are pasted `ms check` output; rejections under the new rule are marked proposed.
- Direction (Chinmay, 2026-10-28): "let's find the crux of the problem and propose point solution for that"; "iterate a few times to simplify and ensure it truly increases confidence in agent generated code, do 3 consecutive runs with skeptic review".
- Skeptic review round 1 (`architecture/opaque-types-review-1.md`, project files): REVISE. Resolved here: collection copies are a prerequisite; opacity reuses the `Resource` class and the computed `Clonable` property instead of a tag and an `impl Clonable` opt-in; generics are closed by bounds at definition; `RelPath`/`HttpUrl`, #1537, factory functions, and the stdlib adoption PR are dropped; trust boundary and do-nothing restated.
- Skeptic review round 2 (`opaque-types-review-2.md`): REVISE. Resolved here: opaque values are classed `Move`, not `Resource`, so no close path is touched; the interpolation bound is narrowed to types that hold an opaque type plus bare type variables (zero such sites in `stdlib/`); the defaulted-marker hole is stated and reported by `ms review`; `Equal` and `Hashable` are never derived; alternatives cannot be opaque; line references refreshed.
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
- Two more escapes, verified: a generic `def show[T](v: T) -> String: f"{v}"` renders anything; `[h].concat([h])`, `take`, `reversed`, `filter`, `find`, and `List.clone()` duplicate elements of any class, including `Closeable` (review round 1 ran one `close` three times).
- A record of scalars copies implicitly (`Money(cents: 5)` passed twice checks clean), so it has no owner.
- The stdlib has the same problem with itself: `Entry`, `Inbox`, `Open` (`stdlib/tasks.ms:287`, `processes.ms:106`, `:307`) are exported only because a public record holds them, and are documented "Internal state".
- Non-goals: must-consume (dropping an approval is allowed), typestate tooling, import restriction, who may edit a module, proving value facts.

## Design

Rule: an exported record with a hidden field that has no default is opaque. A hidden field is one whose type is private to the declaring module (`private-field-types`: the closure check in `contracts.rs` `fn public`, line 1034, skips record fields; the field is inaccessible elsewhere). A hidden field with a default keeps that proposal's behavior (constructible, field hidden), which is what `TaskGroup` and `ProcessGroup` need and what their 39 call sites use.

Outside the declaring file an opaque type:

- cannot be constructed, and no field can be read, written, or named in a pattern, including public-typed fields. `impl` blocks elsewhere follow the same rule.
- cannot be used through an `impl` block in another file either; the field ban is by declaring file.

Everywhere, including inside the module:

- the computed properties `Clonable`, `Equal`, and `Hashable` (`contracts.rs:613`, `:758`) are false for an opaque type and for any type holding one, in every file. The module may `impl Equal` or `Hashable`; it copies a value by destructuring and rebuilding. `holds_resource` (`contracts.rs:673`, the set-element and map-key gate from #1887) gains the same `holds_opaque` test.
- the value is classed at least `Move` in `crates/ms-check/src/ownership/classify.rs` (`nominal`, line 90, today starts the fold at `Copy`): it moves at its last use and never copies implicitly, even when every other field is a scalar. `Move` without `Clonable` is what an interface value is today, so no close path is involved: an unspent approval is dropped silently, and `with` rejects it as not `Closeable`. (Round 2 showed `Resource` would mean must-close and fail in `ms-lower/src/with.rs:380`.)
- `parse[T]` (`stdlib/json.ms:174`), `stringify[T]` (`:258`), `cli.decode[T]` (`cli.ms:298`), `processes.decode[T]` (`processes.ms:131`), and string interpolation reject an argument whose type holds an opaque type (`holds_opaque`, transitive through `Optional`, `Result`, `List`, records, alternatives). Interfaces, `Closeable` records, and everything else render as today.
- a bare type variable in one of those positions needs `T: Clonable`, checked at the definition as `v.clone()` on an unbounded `T` is today ("unknown member clone on T"). This is the only way a generic wrapper could render an opaque value, and `stdlib/` has no such site (measured: no `f"{` inside a generic `def` in `collections.ms`, `test.ms`, `core.ms`, `json.ms`). `make verify-full` counts the rest.
- inside the module, destructuring an opaque value moves the named parts out and consumes it (a partial move out of a record; #1422 keeps a special case for `SharedGuard` in `crates/ms-clif/src/lower.rs:590` that retires onto this).

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
forge.ms:17:16: type: Approved[Delete] is opaque and cannot be rendered
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
| `crates/ms-check` interpolation and the four builders | reject an operand that `holds_opaque`; bare type variable needs `T: Clonable` | reject: `f"{approval}"`, `f"{some(approval)}"`, generic `show[T]`; accept: `f"{err}"` with `err: Error`, `f"{handle}"` on a `Closeable` |
| `crates/ms-tooling` `ms review` | report an exported record becoming constructible outside its module | tooling test: default added to hidden field; hidden type exported |
| `stdlib/tasks.ms`, `processes.ms` | un-export `Entry`, `Inbox`, `Open` | existing fixtures |
| lowering, MIR, codegen, `ms-rt`, ABI, parser, formatter, lint, LSP | unchanged (`Move` values take no close path) | existing |
| `documentation/core-language/types/records.md`, `modules/boundaries.md`, `glossary.md` | hidden field, opaque, consuming destructure | `make docs`, repo-check |
| platform parity | checker and `.ms` only | CI matrix, nothing gated |

## Alternatives

- Do nothing: `forge.ms` and the collection bug stay accepted; the stdlib keeps exporting internal state.
- A lint ("construct, parse, clone, or interpolate a record declared in another module"): catches `forge.ms` as written and is the honest baseline. It cannot see through generics, collection methods, or implicit copies, which is exactly where the review found the leaks; the rule's marginal value is that the ownership checker tracks those already. No measurement shows agents forge approvals; the stdlib's own "Internal state" exports show the discipline fails without the compiler.
- `private-field-types` alone: closes field access; defaults, `parse`, `.clone()`, copies, and interpolation stay open.
- A `structural` tag in `bindings.json` (first draft): a second mechanism with no rule for generic instantiation. `holds_opaque` is one transitive property like `holds_resource`, and the bound closes generics at definition.
- `T: Clonable` on every interpolation (second draft): breaks `f"{err}"` for every interface value, since contracts are never `Clonable`. Narrowed to opaque-holding types and bare variables.
- Classing opaque values `Resource` (second draft): `Resource` means must-close, and a record with no `close` fails in lowering. `Move` is the right class.
- An `opaque` modifier: same semantics, new grammar, formatter, LSP, docs. "No default on a private field" already says only the module can supply it.
- Drawbacks: a field like `seal: Seal` is the marker, not self-explaining, and one added default removes the guarantee silently (mitigated by `ms review`); a generic that renders a bare `T` must add `T: Clonable`; collection methods gain a bound that may break code holding resources in lists, which is the bug.

## Staging and verification

- PR 1, prerequisite: collection bounds and fixtures. Gate: `make verify-full`, since stdlib and e2e code may hold resources in lists.
- PR 2: hidden fields, opaque check, classifier line, `holds_opaque` on the four builders and interpolation, the `ms review` report, docs, `forge.ms` and `gate.ms` as conformance reject and accept cases, the un-exports. Gate: `make verify`.
- Evidence: the two fixtures and the stdlib un-exports; no benchmark claimed.

## Open questions

- Bare type variable in a rendering position: require `T: Clonable` (recommended; existing mechanism, no stdlib site affected) or accept the generic-wrapper leak and document it.
- The implicit marker: accept it with the `ms review` report (recommended; no syntax) or add an explicit marker later if the report proves insufficient.
