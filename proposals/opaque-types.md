# Opaque types and import permissions

## Summary

- Problem: a value a human-owned module hands out (a secret, a validated input, an approval) can be re-minted or read by agent code outside that module: construction, field access, `json.parse`, `f"{value}"`, and `to_string()` all work on any exported record (`forge.ms` below checks clean on main `23129640`).
- Change: `opaque type` hides every field outside the declaring module (no construction, access, or pattern); rendering an opaque value prints only its type name; `parse` and the other decoders cannot build one. Copy, clone, equality, and hashing follow the fields as today. An `[imports]` allow list in `ms.toml` says which files may import which modules, so agent files cannot reach the raw modules the opaque types wrap.
- Cost: one keyword in the parser and formatter, an opaque check in `ms-check`, the name-only text and JSON forms in `ms-lower`, one manifest table and one check at import resolution.
- Decision requested: approve the keyword, the name-only rendering, and the `[imports]` table.

## Status

- Proposal, 2026-10-28, against main `23129640`. Examples under the new rule are marked proposed.
- Direction (Chinmay, 2026-10-28): "opaque type should be a keyword that hides all its fields, so we only print name of type in strings and parse can't construct it, instantiating it outside the module should be an error, but this needs to be coupled with permission limitation wrt who can import what, otherwise it's not useful"; "keep the proposal short"; `opaque` over `restricted`; "why no clone copy etc, i think if we restrict methods it's not gonna be that useful".
- Three skeptic rounds on the keyword-free draft (`architecture/opaque-types-review-1.md` to `-3.md`, project files) covered a move-only variant; the keyword removes its implicit marker, name-only rendering removes its bare-`T` question, and the owner dropped move-only itself.
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
    let line = f"{a}" + a.to_string()
    let n = a.nonce.length()
    return spend(a, "u2").get("").length() + spend(decode(), "u2").get("").length() + line.length() + n
```

- A library cannot close these: it does not see decoders or rendering, and a lint sees names, not the generic wrapper that renders a `T`.
- Hiding alone is not enough: `forge.ms` can import `@std/fs.ms` and write the file the `Disk` abstraction was meant to meter.
- Non-goals: must-consume (dropping an approval is allowed), typestate tooling, proving value facts, who may edit a module (CODEOWNERS).

## Design

`opaque` is a modifier on a record declaration, like `extern`: `export opaque type Approved[T]:`. Outside the declaring file:

- no construction, field read or write, field pattern, or `impl` that touches fields; the module exports the only constructors and accessors.
- everything else is as for any record: copy and move class, `.clone()`, `Clonable`, `Equal`, and `Hashable` are derived from the fields (`contracts.rs:613`, `:758`; `ownership/classify.rs:90`). `opaque` is visibility, not ownership: an opaque value can be duplicated. A module that needs single use gets it from the existing rules by holding a resource or a non-clonable field.

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
forge.ms:12:13: type: field nonce of Approved[Delete] is hidden outside gate.ms
```

Import permissions: `ms.toml` gains one table keyed by importer pattern. The most specific matching pattern decides; a file matching none is unrestricted, so projects without the table change nothing. Relative imports resolve to project paths first; `[aliases]` entries match by resolved path. Module granularity only.

```toml
[imports]
"src/**"   = ["./**", "types/**", "@std/collections.ms", "@std/string.ms", "@std/json.ms"]
"types/**" = ["@std/**", "types/**"]
"tests/**" = ["**"]
```

Diagnostic: "`src/export.ms` may not import `@std/fs.ms` (ms.toml [imports] \"src/**\"); use the abstractions exported by types/". `ms.toml` and `types/` are owned by CODEOWNERS; `ms inspect --imports` prints the effective map.

What holds afterwards: every `Approved` came from `approve` and names the entity the signature named; agent code in `src/` reaches the file system only through `types/`. Both relative to those modules as written. Spending it once is a separate property the module adds by holding a non-clonable field.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-syntax` (`parser.rs:942` for `extern`, `token.rs`), formatter | `opaque` modifier, `RecordDecl.opaque` | parse and format fixtures |
| `crates/ms-check` | opaque check by declaring file; concrete `parse[T]` reject | reject per operation; accept inside the module and for copy, clone, `==`, `List[Approved]` |
| `crates/ms-lower` `text.rs`, `json.rs` | name-only text form; no JSON form; decoder `none` | e2e: `f"{a}"`, generic `show[T]`, `stringify`, `parse` |
| `crates/ms-driver` `project/manifest.rs:1`, `ms-check` import resolution | `[imports]` table, most-specific match, one check | manifest tests; reject and accept fixtures; `ms inspect --imports` |
| MIR, codegen, `ms-rt`, ABI | unchanged | existing |
| docs: `types/records.md`, `modules/boundaries.md`, `glossary.md`, project manifest page | opaque, `[imports]` | `make docs`, repo-check |
| platform parity | compiler and `.ms` only | CI matrix, nothing gated |

## Alternatives

- Do nothing: `forge.ms` stays accepted; policies stay prose.
- A lint for construct/parse/interpolate across modules: catches `forge.ms` as written, cannot see a generic that renders or decodes a `T`.
- Implicit marker (a private field with no default, the three-round draft): no syntax, but one added default silently removes the guarantee, and alternatives cannot carry it. Rejected by the owner.
- Move-only opaque values (same draft): gives "spent at most once" but forbids copy and clone on every opaque value, which the owner judged not useful; single use stays available through resources and non-clonable fields. The collection-copy bug that draft found (`xs.concat(xs)` on one `Closeable` closes it three times) is filed separately.
- Reject rendering at check time instead of printing the name: needs a bound or inferred flag for bare `T`; printing the name is one lowering rule and keeps unconstrained-`T` rendering as documented (`intrinsics.ms:6`).
- `restricted type`: says something is forbidden without saying what, and collides with `Network.restrict` (`net.ms:351`).
- Opaque without `[imports]`: agent code bypasses the abstraction by importing the raw module; owner's point.
- Drawbacks: `[imports]` is a second config surface; a module wanting JSON for an opaque type implements a codec.

## Staging and verification

- PR 1: keyword, check, text and JSON forms, docs; `forge.ms` and `gate.ms` as conformance reject and accept cases. Gate: `make verify`.
- PR 2: `[imports]`. Gate: manifest tests and `make verify`.

## Open questions

- Whether `opaque` also applies to alternatives (`case` types): recommended yes, same rules, cases hidden outside the module.
- Whether a redirecting import map (`@std/fs.ms` served as `types/disk.ms`) is wanted later: recommended no, the allow list keeps what code calls explicit.
