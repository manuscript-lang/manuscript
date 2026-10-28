# Opaque types and import permissions

## Summary

- Problem: a value a human-owned module hands out (an approval, a secret, a validated input) can be re-minted or duplicated by agent code outside that module: construction, implicit copy, `.clone()`, collection copies, `json.parse`, `f"{value}"`, and `to_string()` all work on any exported record (`forge.ms` below checks clean on main `23129640`).
- Change: `opaque type` hides every field outside the declaring module (no construction, access, pattern, clone, implicit copy, derived `Equal`/`Hashable`); rendering any opaque value prints only its type name; `parse` and the other decoders cannot build one. An `[imports]` allow list in `ms.toml` says which files may import which modules, so agent files cannot reach the raw modules the opaque types wrap.
- Cost: one keyword in the parser and formatter, an opaque check and one classifier line in `ms-check`, the name-only text and JSON forms in `ms-lower`, one manifest table and one check at import resolution.
- Prerequisite: `take`, `slice`, `reversed`, `concat`, `filter`, `find` copy non-`Clonable` elements today (`xs.concat(xs)` on one `Closeable` closed it three times); they move under `T: Clonable` interfaces first.
- Decision requested: approve the keyword, the name-only rendering, and the `[imports]` table.

## Status

- Proposal, 2026-10-28, against main `23129640`. Examples under the new rule are marked proposed.
- Direction (Chinmay, 2026-10-28): "opaque type should be a keyword that hides all its fields, so we only print name of type in strings and parse can't construct it, instantiating it outside the module should be an error, but this needs to be coupled with permission limitation wrt who can import what, otherwise it's not useful"; "keep the proposal short"; `opaque` over `restricted`.
- Three skeptic rounds on the keyword-free draft (`architecture/opaque-types-review-1.md` to `-3.md`, project files): the move-class design held; the open items were bare-`T` rendering and the implicit marker. The keyword removes the marker; name-only rendering removes the bare-`T` question.
- Supersedes `resources-for-logic.md` (removed). Extends the project-file proposal `private-field-types.md`.

## Problem

```manuscript
from "./gate.ms" import Approved, Delete, spend
from "@std/json.ms" import parse

def forge() -> Approved[Delete]: Approved[Delete](entity: "u2", nonce: "x")

def decode() -> Approved[Delete]:
    return parse[Approved[Delete]]("{\"entity\":\"u2\",\"nonce\":\"x\"}").get(forge())

export def main() -> Int:
    let a = forge()
    let copy = a.clone()
    let line = f"{a}" + a.to_string()
    return spend(copy, "u2").get("").length() + spend(decode(), "u2").get("").length() + line.length() + a.nonce.length()
```

- Without `.clone()` the checker already rejects a second `spend` ("`a` is moved here but used again"). Ownership is the mechanism; the escapes around it are the problem, and a library cannot see copies, decoders, or rendering.
- A record of scalars copies implicitly, so `Money(cents: 5)` has no owner at all.
- Hiding alone is not enough: `forge.ms` can import `@std/fs.ms` and write the file the `Disk` abstraction was meant to meter.
- Non-goals: must-consume (dropping an approval is allowed), typestate tooling, proving value facts, who may edit a module (CODEOWNERS).

## Design

`opaque` is a modifier on a record declaration, like `extern`: `export opaque type Approved[T]:`. Outside the declaring file:

- no construction, field read or write, field pattern, `.clone()`, or `impl` that touches fields; the module exports the only constructors and accessors.
- `Clonable`, `Equal`, and `Hashable` are never derived (`contracts.rs:613`, `:758`); the module may `impl Equal` or `Hashable`; `holds_resource` (`:673`) also rejects a type holding an opaque value as a set element or map key.
- the value is classed at least `Move` (`ownership/classify.rs:90` folds from `Copy` today): it moves at its last use and never copies implicitly, even with only scalar fields. `Move` without `Clonable` is what an interface value is today, so no close path is involved.

Everywhere, generated per type so generics need no rule:

- text form (`ms-lower/src/text.rs`: interpolation, `to_string`, test output) is the type name: `f"{a}"` is `"Approved[Delete]"`.
- JSON (`ms-lower/src/json.rs`): the encoder returns no form, so `stringify` reports a value without a JSON form; the decoder returns `none`, so `parse` and `cli`/`processes` decoding fail with `InvalidData`. A concrete `parse[Approved[Delete]]` call is also a check error.

```manuscript
# gate.ms, proposed
export opaque type Approved[T]:
    entity: String
    nonce: String

export def approve(request: SignedRequest) -> Result[Approved[Delete], GateError]:
    let {entity, nonce, signature} = request
    if signature != f"sig({entity},{nonce})": return error(BadSignature)
    return ok(Approved[Delete](entity: entity, nonce: nonce))

export def spend(approval: Approved[Delete], entity: String) -> Result[String, GateError]:
    let {entity: approved, nonce} = approval
    if approved != entity: return error(WrongEntity)
    return ok(nonce)
```

```text
forge.ms:4:34: type: Approved[Delete] is opaque outside gate.ms; build it with approve
forge.ms:7:12: type: parse cannot build Approved[Delete]; it is opaque
forge.ms:11:16: type: unknown member clone on Approved[Delete]; it is opaque outside gate.ms
forge.ms:13:106: type: field nonce of Approved[Delete] is hidden outside gate.ms
```

Import permissions: `ms.toml` gains one table keyed by importer pattern. The most specific matching pattern decides; a file matching none is unrestricted, so projects without the table change nothing. Relative imports resolve to project paths first; `[aliases]` entries match by resolved path. Module granularity only.

```toml
[imports]
"src/**"   = ["./**", "types/**", "@std/collections.ms", "@std/string.ms", "@std/json.ms"]
"types/**" = ["@std/**", "types/**"]
"tests/**" = ["**"]
```

Diagnostic: "`src/export.ms` may not import `@std/fs.ms` (ms.toml [imports] \"src/**\"); use the abstractions exported by types/". `ms.toml` and `types/` are owned by CODEOWNERS; `ms inspect --imports` prints the effective map.

What holds afterwards: every `Approved` came from `approve` and was spent at most once; agent code in `src/` reaches the file system only through `types/`. Both relative to those modules as written.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/collections.ms` (prerequisite) | element-copying methods under `T: Clonable` interfaces (`ListExtremes` pattern, `:568`) | reject: `concat` on a list of `Closeable` |
| `crates/ms-syntax` (`parser.rs:942` for `extern`, `token.rs`), formatter | `opaque` modifier, `RecordDecl.opaque` | parse and format fixtures |
| `crates/ms-check` | opaque check by declaring file; properties false; classifier line; concrete `parse[T]` reject | reject per operation; accept inside module, `List[Approved]` in scope, unspent value dropped, `with` rejected, `Set[Approved]` rejected |
| `crates/ms-lower` `text.rs`, `json.rs` | name-only text form; no JSON form; decoder `none` | e2e: `f"{a}"`, generic `show[T]`, `stringify`, `parse` |
| `crates/ms-driver` `project/manifest.rs:1`, `ms-check` import resolution | `[imports]` table, most-specific match, one check | manifest tests; reject and accept fixtures; `ms inspect --imports` |
| MIR, codegen, `ms-rt`, ABI | unchanged | existing |
| docs: `types/records.md`, `modules/boundaries.md`, `glossary.md`, project manifest page | opaque, `[imports]` | `make docs`, repo-check |
| platform parity | compiler and `.ms` only | CI matrix, nothing gated |

## Alternatives

- Do nothing: `forge.ms` and the collection bug stay accepted; policies stay prose.
- A lint for construct/parse/clone/interpolate across modules: catches `forge.ms` as written, cannot see generics, collection copies, or implicit copies.
- Implicit marker (a private field with no default, the three-round draft): no syntax, but one added default silently removes the guarantee, and alternatives cannot carry it. Rejected by the owner.
- Reject rendering at check time instead of printing the name: needs a bound or inferred flag for bare `T`; printing the name is one lowering rule and keeps unconstrained-`T` rendering as documented (`intrinsics.ms:6`).
- `restricted type`: says something is forbidden without saying what, and collides with `Network.restrict` (`net.ms:351`).
- Opaque without `[imports]`: agent code bypasses the abstraction by importing the raw module; owner's point.
- Drawbacks: a breaking stdlib change in the prerequisite for code holding resources in lists (the bug); `[imports]` is a second config surface; a module wanting `==` or JSON implements it.

## Staging and verification

- PR 1: collection bounds and fixtures. Gate: `make verify-full`.
- PR 2: keyword, check, classifier, text and JSON forms, docs; `forge.ms` and `gate.ms` as conformance reject and accept cases. Gate: `make verify`.
- PR 3: `[imports]`. Gate: manifest tests and `make verify`.

## Open questions

- Whether `opaque` also applies to alternatives (`case` types): recommended yes, same rules, cases hidden outside the module.
- Whether a redirecting import map (`@std/fs.ms` served as `types/disk.ms`) is wanted later: recommended no, the allow list keeps what code calls explicit.
