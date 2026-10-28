# Opaque types

## Summary

- Problem: a value that a human-owned module hands out (an approval, a secret, a validated path) can be re-minted or duplicated by agent code outside that module. Construction, implicit copy, `.clone()`, `json.parse`, and `f"{value}"` all work on any exported record, so a "use once, for this entity" policy is advisory.
- Change: one rule. A record with a hidden field (a field of a private type) is **opaque** outside its module: no construction, no field access, no destructuring, no clone, no implicit copy, and no structural conversion. Inside the module, destructuring consumes it.
- Cost: a checker rule family in `crates/ms-check` and a `structural` tag on five `bindings.json` entries. No syntax, no keyword, no runtime change.
- Benefit: the existing use-after-move check becomes a policy tool. Single use, "for this entity only", and "never logged" are then enforced by `ms check` for any type a human writes this way.
- Decision requested: approve the rule and the consuming-destructure semantics.

## Status

- Proposal, 2026-10-28, checked against main `bb57ea58` (examples ran on the `5664578e` build). Accepted examples are pasted output; rejected examples under the new rule are marked proposed.
- Direction (Chinmay, 2026-10-28): "is there prior art on this? this feels like it's handled historically by libraries"; "what's the real benefit here"; "let's find the crux of the problem and propose point solution for that".
- Supersedes `resources-for-logic.md` (removed, history in git): `Linear`, typestate tooling, frozen modules, and the `[imports]` allow list are dropped from this proposal; see Alternatives. Extends the project-file proposal `private-field-types.md`, which asked for hidden fields and whose "opaque export" comparison this resolves without a modifier.
- Related: issue #1868 (`structural` tag), #1422 and #1537 (both need a partial move out of a record).

## Problem

`gate.ms` mints an approval only from a signed request and takes it apart once in `spend`. `forge.ms` is agent-written and defeats every part of that, with no diagnostic (`ms check forge.ms`: `Checked forge.ms`):

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

- Without `.clone()` on line 10 the checker already rejects the second `spend`: "`a` is moved here but used again at 11:24; a value has one owner". The ownership rule is the right one; the four escapes around it are the problem.
- A record whose fields are all scalars copies implicitly (`Money(cents: 5)` passed twice checks clean), so it has no owner at all.
- A library cannot close any of these: it does not see copies, decoders, or interpolation. Linters (`no-restricted-imports`, ArchUnit) restrict names, not values. Move and Austral close them in the language; so does this.
- Non-goals: must-consume (a dropped approval is allowed), typestate tooling, import restriction, proving value facts, OS sandboxing.

## Design

Rule: an exported record with at least one hidden field is opaque outside its declaring module. A hidden field is one whose type is private to that module (the `private-field-types` derivation). Outside the module:

- Construction of the record is an error, with or without defaults. (`private-field-types` filled defaulted hidden fields; this rule does not, since a default would be a public constructor again.)
- Reading, writing, or destructuring any field is an error, including public-typed fields.
- `.clone()` is an error unless the module implements `Clonable` for the type. No equality or hashing is derived.
- The value is move-only: it never copies implicitly, even when every field is a scalar.
- A `structural` tag in `stdlib/bindings.json` marks generic builders and renderers: `json.parse[T]`, `json.stringify`, `cli.decode[T]`, `processes.decode[T]`, string interpolation, and the `@std/test.ms` renderers. A tagged call with an opaque type argument, or whose argument type contains one, is an error. The module opts in by implementing the explicit interface (`Display`, a codec).

Inside the module:

- Everything is accessible as today, with one change: destructuring moves the named parts out and consumes the record. This is a partial move out of a record, the primitive that #1422 (`SharedGuard` glue in `crates/ms-clif/src/lower.rs`) and #1537 both special-case; both retire onto it.
- Ownership, drop, cancellation, and codegen are unchanged: an opaque value is an ordinary record that the checker refuses to copy.

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

Proposed diagnostics for `forge.ms` under the rule:

```text
forge.ms:4:34: type: Approved[Delete] is opaque outside gate.ms; build it with approve
forge.ms:7:12: type: parse builds its result structurally, which Approved[Delete] does not allow; build it with approve
forge.ms:10:23: type: Approved[Delete] is opaque outside gate.ms and cannot be cloned
forge.ms:17:16: type: Approved[Delete] is opaque outside gate.ms and cannot be rendered
forge.ms:18:60: type: field nonce of Approved[Delete] is hidden outside gate.ms
```

What the rule then guarantees, by the existing move checker: one `Approved[Delete]` per `approve`, spent at most once, only for the entity the signature named, never printed. The gate module's own code is the trust boundary, as it is for memory today.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-check/src/contracts.rs` (`fn public`) | record fields skip the closure check; derive hidden fields | accept: exported record with a private-typed field |
| `crates/ms-check` records, members, patterns | opaque rule: construction, access, destructuring, clone outside the module | one reject fixture per operation, one accept inside the module |
| `crates/ms-check` ownership | opaque types never copy; in-module destructuring is a partial move | reject: scalar-only token used twice; accept: `spend` consumes |
| `crates/ms-check` calls | `structural` tag rejects opaque type arguments | reject: `parse[T]`, `stringify`, `decode[T]`, `f"{v}"`, `expect_equal` |
| `stdlib/bindings.json` | `structural` on the five entries | audit test: every generic builder or renderer is tagged |
| `stdlib/tasks.ms`, `processes.ms`, `queue.ms` | un-export `Entry`, `TaskChannels`, `Open`, `Inbox`, `PriorityEntry`; `TaskGroup()`/`ProcessGroup()` become factory functions | existing fixtures |
| `stdlib/fs.ms`, `net.ms` | `RelPath`, `HttpUrl` gain a hidden field so `relative_path`/`http_url` are the only constructors | reject: `RelPath("../x")` |
| `crates/ms-clif/src/lower.rs` | retire the `SharedGuard` glue special case onto partial move | e2e |
| parser, lowering, MIR, codegen, `ms-rt`, ABI, formatter | unchanged | existing |
| lint, LSP, VS Code | hover shows "opaque outside <module>" | LSP test |
| `documentation/core-language/types/records.md`, `modules/boundaries.md`, `glossary.md` | hidden field, opaque, consuming destructure | `make docs`, repo-check |
| platform parity | checker and `.ms` only | CI matrix, nothing gated |

## Alternatives

- Do nothing: `RelPath("../x")`, forged approvals, and logged secrets stay accepted; #1422 and #1537 keep their special cases.
- `private-field-types` as written (derived hiding, defaults fill hidden fields, copy and render unchanged): closes field access only; the forge program still checks clean through defaults, `parse`, `.clone()`, and interpolation.
- An `opaque` modifier on `export type`: same semantics, new grammar, formatter, LSP, and docs surface. A private field already says it and needs no syntax.
- `Linear` (must-consume), typestate tooling, `[imports]` allow list, frozen modules (the superseded proposal): each is a separate benefit without a hard guarantee behind it; they can return as their own proposals once this rule has evidence.
- Library-only: newtypes and builders in other languages leak through exactly the four escapes above; see Problem.
- Drawbacks: opaque types need accessor functions; `TaskGroup()` and `ProcessGroup()` become factory functions (a breaking stdlib change); a module that wants `==` or JSON writes the interface itself.

## Staging and verification

- One PR: checker rules and fixtures, `structural` tags, docs. Gate: `make verify`, every reject fixture quoting its diagnostic, `forge.ms` as a conformance reject case, `gate.ms` as an accept case.
- Second PR: stdlib adoption (un-exports, `RelPath`/`HttpUrl`, factory functions) and the #1422 cleanup. Gate: `make verify-full`.
- Measurement: the forge program and the stdlib validators are the evidence; no benchmark is claimed.

## Open questions

- `TaskGroup()` and `ProcessGroup()`: factory functions `task_group()`/`process_group()` (recommended, matches `relative_path`), or keep defaults filling hidden fields for those two types only.
- Whether opaque values may live in `List`, `Map`, `Channel`, and `Shared`: recommended yes, since they are ordinary moved values; only copy and structural conversion are refused.
