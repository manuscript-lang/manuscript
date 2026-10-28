# Opaque types and import permissions

## Summary

- Principle (Chinmay, 2026-10-28): hide the details of an operation and route all access through one point where checks are enforced. Two rules apply it at two levels: `opaque type` makes a module the only way to build or read a value, and `[imports]` makes a set of modules the only way to reach another module.
- Problem: a value a human-owned module hands out (a secret, a validated input, an approval) can be re-minted or read by agent code outside that module: construction, field access, `json.parse`, `f"{value}"`, and `to_string()` all work on any exported record (`forge.ms` below checks clean on main `accb4d6d`).
- Change: `opaque type` hides every field outside the declaring module (no construction, access, or pattern); rendering an opaque value prints only its type name; `parse` and the other decoders cannot build one. Copy, clone, and equality follow the fields as today; hashing is not derived (Open questions). An `[imports]` allow list in `ms.toml` says which files may import which modules, so agent files cannot reach the raw modules the opaque types wrap.
- Cost: one keyword in the parser and formatter, an opaque check in `ms-check`, the name-only text and JSON forms in `ms-lower`, one manifest table and one check at import resolution.
- Guarantee, stated exactly: a value of an opaque type was built in its module. Not single use: a copy replays an approval. Not scoped exports: a `test_approval()` the module exports for tests is callable from `src/` too.
- Decision requested: approve the keyword, the name-only rendering, and the `[imports]` table.

## Status

- Proposal, 2026-10-28, against main `accb4d6d`. Examples under the new rule are marked proposed.
- Direction (Chinmay, 2026-10-28): "opaque type should be a keyword that hides all its fields, so we only print name of type in strings and parse can't construct it, instantiating it outside the module should be an error, but this needs to be coupled with permission limitation wrt who can import what, otherwise it's not useful"; "keep the proposal short"; `opaque` over `restricted`; "why no clone copy etc, i think if we restrict methods it's not gonna be that useful".
- Skeptic review round 4 (`opaque-types-review-4.md`) on the keyword version: REVISE, "then approvable"; name-only rendering judged sound. Resolved here: decoder list derived from `parse` callers and rejection of types that hold an opaque type, `Hashable` and the replay and test-helper gaps stated, glob specificity and one shared import check defined, citations fixed.
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

`opaque` is a modifier on a record or alternative declaration, like `extern`: `export opaque type Approved[T]:`. Outside the declaring file:

- no construction, field read or write, field pattern, `match` on cases, or `impl` that touches fields or cases; the module exports the only constructors and accessors.
- everything else is as for any record: copy and move class, `.clone()`, `Clonable`, and `Equal` are derived from the fields (`contracts.rs:613`, `:758`; `ownership/classify.rs:90`). `opaque` is visibility, not ownership: an opaque value can be duplicated (`.clone()`, `collections.filled`), so single use is not provided; a module that needs it holds a resource or a non-clonable field. `Hashable` is not derived, because `hash()` is a stable function of the hidden fields and would be an offline oracle for a low-entropy secret; the module may `impl Hashable`.

Everywhere, generated per type so generics need no rule:

- text form (`ms-lower/src/text.rs`: interpolation, `to_string`, test output) is the type name: `f"{a}"` is `"Approved[Delete]"`.
- JSON (`ms-lower/src/json.rs`): the encoder returns no form and the decoder returns `none`, so a bare-`T` instantiation reports a value without a JSON form or `InvalidData` at runtime, echoing nothing. With a concrete type the check rejects every JSON entry point whose type argument holds an opaque type (transitive, like `holds_resource`, `contracts.rs:673`): the decoders, derived from the callers of `parse`, are `json.parse` (`json.ms:174`), `fetch` `Response.json[T]` (`fetch.ms:117`), `cli.command[T]` (`cli.ms:285`), and the channel receive through `processes.decode` (`processes.ms:131`); the encoders are `json.stringify` (`:258`), `http.json` (`http.ms:504`), `fetch.json_body` (`:66`), `log.record` (`log.ms:268`), and `processes.encode` (`:124`). A failing `expect_equal` on an opaque value prints only the type name.

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

Import permissions: `ms.toml` gains one table keyed by importer pattern over project paths. The matching pattern with the longest literal prefix (the text before its first `*`) decides; two matching patterns with equal prefixes are a manifest error; a file matching none, or a file with no `ms.toml`, is unrestricted, so existing projects change nothing. Both the importer and the imported path are project-relative after resolution, so relative imports and `[aliases]` are matched by resolved path and are not a bypass. One predicate serves `resolve_import` (`ms-driver/src/project/paths.rs:11`, local and alias imports) and the checker's `@std` resolution. Module granularity only: allowing `@std/net.ms` allows any socket; narrowing a module's reach is `Network.restrict` (`net.ms:470`), not this table.

```toml
[imports]
"src/**"   = ["src/**", "types/**", "@std/collections.ms", "@std/string.ms", "@std/json.ms"]
"types/**" = ["@std/**", "types/**"]
"tests/**" = ["**"]
```

Diagnostic: "`src/export.ms` may not import `@std/fs.ms` (ms.toml [imports] \"src/**\"); use the abstractions exported by types/". `ms.toml` and `types/` are owned by CODEOWNERS; an agent that may edit `ms.toml` is not restricted.

What holds afterwards: every `Approved` came from `approve` and names the entity the signature named; agent code in `src/` reaches the file system only through `types/`. Both relative to those modules as written. Spending it once is a separate property the module adds by holding a non-clonable field.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-syntax` (`parser.rs:942` for `extern`, `token.rs`), formatter | `opaque` modifier, `RecordDecl.opaque` | parse and format fixtures |
| `crates/ms-check` | opaque check by declaring file; `holds_opaque` rejects the JSON entry points; `Hashable` not derived | reject per operation and per entry point, `Set[Approved]`; accept inside the module and for copy, clone, `==`, `List[Approved]` |
| `crates/ms-lower` `text.rs`, `json.rs` | name-only text form; no JSON form; decoder `none` | e2e: `f"{a}"`, generic `show[T]`, `stringify`, `parse` |
| `crates/ms-driver` `project/manifest.rs:1`, `paths.rs:11`, `ms-check` `@std` resolution | `[imports]` table, longest-literal-prefix match, one shared predicate | manifest tests incl. the tie error; reject fixtures for a local, alias, and `@std` import; accept for a listed one |
| MIR, codegen, `ms-rt`, ABI | unchanged | existing |
| docs: `types/records.md`, `modules/boundaries.md`, `glossary.md`, project manifest page | opaque, `[imports]` | `make docs`, repo-check |
| platform parity | compiler and `.ms` only | CI matrix, nothing gated |

## Alternatives

- Do nothing: `forge.ms` stays accepted; policies stay prose.
- A lint for construct/parse/interpolate across modules: catches `forge.ms` as written, cannot see a generic that renders or decodes a `T`.
- Implicit marker (a private field with no default, the three-round draft): no syntax, but one added default silently removes the guarantee, and alternatives cannot carry it. Rejected by the owner.
- Move-only opaque values (same draft): gives "spent at most once" but forbids copy and clone on every opaque value, which the owner judged not useful; single use stays available through resources and non-clonable fields. The collection-copy bug that draft found (`xs.concat(xs)` on one `Closeable` closed it three times) is #1900, fixed in #1901.
- Reject rendering at check time instead of printing the name: needs a bound or inferred flag for bare `T`; printing the name is one lowering rule and keeps unconstrained-`T` rendering as documented (`intrinsics.ms:6`).
- `restricted type`: says something is forbidden without saying what, and collides with `Network.restrict` (`net.ms:470`).
- Opaque without `[imports]`: agent code bypasses the abstraction by importing the raw module; owner's point.

## Staging and verification

- PR 1: keyword, check, text and JSON forms, docs; `forge.ms` and `gate.ms` as conformance reject and accept cases. Gate: `make verify`.
- PR 2: `[imports]`. Gate: manifest tests and `make verify`.

## Open questions

- `Hashable` for opaque types: not derived (recommended; `hash()` is an oracle of the hidden fields) or derived like `Equal` so opaque values can key a `Map` without a module `impl`.
