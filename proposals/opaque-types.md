# Opaque types

## Summary

- Problem: a value that a human-owned module hands out (an approval, a secret, a validated input) can be re-minted or duplicated by agent code outside that module. Construction, implicit copy, `.clone()`, collection copies, `json.parse`, and `f"{value}"` all work on any exported record, so "use once, for this entity" is advisory.
- Change: one rule. An exported record with a hidden field that has no default is **opaque**: outside its module it cannot be built, read, written, destructured, or cloned; everywhere it is a move-only, non-`Clonable` value, the class `Closeable` records already have. Generic builders and renderers require `T: Clonable`, so an opaque value cannot be decoded, encoded, or rendered, and a generic wrapper cannot do it either.
- Prerequisite: collection methods that copy elements (`take`, `slice`, `reversed`, `concat`, `filter`, `find`) accept non-`Clonable` elements today; `xs.concat(xs)` on a list of one `Closeable` closes it three times. They move under `T: Clonable` interfaces first.
- Cost: hidden-field derivation and an opaque check in `crates/ms-check`, one line in the ownership classifier, `Clonable` bounds on four stdlib declarations and interpolation. No syntax, no runtime change.
- Decision requested: approve the rule, the `Clonable` bound on interpolation (a `Closeable` record can no longer be rendered by default), and the prerequisite PR.

## Status

- Proposal, 2026-10-28, checked against main `b7b349e5`. Accepted and leaking examples are pasted `ms check` output; rejections under the new rule are marked proposed.
- Direction (Chinmay, 2026-10-28): "let's find the crux of the problem and propose point solution for that"; "iterate a few times to simplify and ensure it truly increases confidence in agent generated code, do 3 consecutive runs with skeptic review".
- Skeptic review round 1 (`architecture/opaque-types-review-1.md`, project files): REVISE. Resolved here: collection copies are a prerequisite; opacity reuses the `Resource` class and the computed `Clonable` property instead of a tag and an `impl Clonable` opt-in; generics are closed by bounds at definition; `RelPath`/`HttpUrl`, #1537, factory functions, and the stdlib adoption PR are dropped; trust boundary and do-nothing restated.
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

Rule: an exported record with a hidden field that has no default is opaque. A hidden field is one whose type is private to the declaring module (`private-field-types`: the closure check in `contracts.rs` `fn public`, line 1001, skips record fields; the field is inaccessible elsewhere). A hidden field with a default keeps that proposal's behavior (constructible, field hidden), which is what `TaskGroup` and `ProcessGroup` need and what their 39 call sites use.

Outside the declaring file an opaque type:

- cannot be constructed, and no field can be read, written, or named in a pattern, including public-typed fields. `impl` blocks elsewhere follow the same rule.
- has no `.clone()`, `equals`, or `hash`: the computed properties `Clonable`, `Equal`, `Hashable` (`contracts.rs:613`, `:725`) are false for it. The module may `impl Equal`/`Hashable`; there is nothing to implement for `Clonable`, so the module exports a copy function if it wants one.

Everywhere, including inside the module:

- the value is classed `Resource` in `crates/ms-check/src/ownership/classify.rs` (`nominal`, line 74), as a `Closeable` record is: it moves at its last use and never copies implicitly, even when every other field is a scalar. Scope-end close applies only to types with `close`; an opaque value without one is dropped.
- generic builders and renderers require `T: Clonable`: `parse[T]` (`stdlib/json.ms:174`), `stringify[T]` (`:258`), `cli.decode[T]` (`cli.ms:298`), `processes.decode[T]` (`processes.ms:131`), and the operand of string interpolation. A generic `show[T](v: T)` that interpolates `v` fails at its definition ("add the bound `T: Clonable`"), as `v.clone()` on an unbounded `T` does today, so instantiation needs no separate rule. A module renders its type by implementing an explicit interface.
- inside the module, destructuring an opaque value moves the named parts out and consumes it (a partial move out of a record; #1422 keeps a special case for `SharedGuard` in `crates/ms-clif/src/lower.rs:583` that retires onto this).

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
forge.ms:7:12: type: parse requires T: Clonable, and Approved[Delete] is opaque
forge.ms:10:23: type: unknown member clone on Approved[Delete]; it is opaque outside gate.ms
forge.ms:17:16: type: interpolation requires a Clonable value, and Approved[Delete] is opaque
forge.ms:18:60: type: field nonce of Approved[Delete] is hidden outside gate.ms
```

What holds afterwards, by the existing move checker: every `Approved[Delete]` came from `approve`, is spent at most once, names the entity the signature named, and is never rendered or encoded. The guarantee is relative to `gate.ms` as written; who may change `gate.ms` is a repository question (CODEOWNERS), not a checker one, and `ms review` already ranks signature changes to it.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/collections.ms` (prerequisite) | element-copying methods under `T: Clonable` interfaces | reject: `concat` on a list of `Closeable`; accept on `Int` |
| `crates/ms-check/src/contracts.rs` | fields skip `public`; hidden-field derivation; opaque types fail `Clonable`/`Equal`/`Hashable` | accept: exported record with private-typed field |
| `crates/ms-check` records, members, patterns | opaque check by declaring file | one reject fixture per operation; accept inside the module |
| `crates/ms-check/src/ownership/classify.rs` | opaque record is `Resource` | reject: scalar-only token used twice; accept: `spend` consumes |
| `crates/ms-check` interpolation | operand must be `Clonable` or implement the display interface | reject: `f"{approval}"`, generic `show[T]` |
| `stdlib/json.ms`, `cli.ms`, `processes.ms` | `T: Clonable` on `parse`, `stringify`, `decode` | reject fixtures |
| `stdlib/tasks.ms`, `processes.ms` | un-export `Entry`, `Inbox`, `Open` | existing fixtures |
| lowering, MIR, codegen, `ms-rt`, ABI, parser, formatter, lint, LSP | unchanged (scope-end close already keyed on `close`; verify in lowering) | existing |
| `documentation/core-language/types/records.md`, `modules/boundaries.md`, `glossary.md` | hidden field, opaque, consuming destructure | `make docs`, repo-check |
| platform parity | checker and `.ms` only | CI matrix, nothing gated |

## Alternatives

- Do nothing: `forge.ms` and the collection bug stay accepted; the stdlib keeps exporting internal state.
- A lint ("construct, parse, clone, or interpolate a record declared in another module"): catches `forge.ms` as written and is the honest baseline. It cannot see through generics, collection methods, or implicit copies, which is exactly where the review found the leaks; the rule's marginal value is that the ownership checker tracks those already. No measurement shows agents forge approvals; the stdlib's own "Internal state" exports show the discipline fails without the compiler.
- `private-field-types` alone: closes field access; defaults, `parse`, `.clone()`, copies, and interpolation stay open.
- A `structural` tag in `bindings.json` (previous draft): a second mechanism beside bounds, with no rule for generic instantiation. `T: Clonable` is the existing one.
- An `opaque` modifier: same semantics, new grammar, formatter, LSP, docs. "No default on a private field" already says only the module can supply it.
- Drawbacks: a dummy field like `seal: Seal` is the marker, which is not self-explaining and needs a glossary entry; `f"{handle}"` on a `Closeable` record stops working by default (verified accepted today); collection methods gain a bound that may break code holding resources in lists, which is the bug.

## Staging and verification

- PR 1, prerequisite: collection bounds and fixtures. Gate: `make verify-full`, since stdlib and e2e code may hold resources in lists.
- PR 2: hidden fields, opaque check, classifier line, bounds on the four declarations and interpolation, docs, `forge.ms` and `gate.ms` as conformance reject and accept cases, the un-exports. Gate: `make verify`.
- Evidence: the two fixtures and the stdlib un-exports; no benchmark claimed.

## Open questions

- Interpolation bound: require `Clonable` (recommended; closes the generic wrapper leak with the existing mechanism) or exempt `Closeable` records to keep `f"{handle}"` working.
- `Equal` for opaque types: never derived (recommended) or derived from the non-hidden fields.
