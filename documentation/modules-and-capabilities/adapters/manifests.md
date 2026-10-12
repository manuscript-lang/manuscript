+++
title = "Adapter manifests"
weight = 83
+++

# Adapter manifests

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Adapters are trusted Go implementations of operation contracts. Every exposed value must be safe for concurrent access. The [standard API contract](../../standard-library/types/prelude.md) defines source semantics; a manifest binds implementations to those semantics.

## Interface modules and package direction

A local adapter ships a `.ms` interface module containing exported data and contracts, with no function bodies, tests, or implementation blocks. It may import standard modules through `@std/...ms` and other registered interface modules. Signatures use intrinsic types, explicitly imported standard types, or public declarations in that interface graph, never application-defined types. Source imports interface declarations through ordinary `.ms` paths.

Each interface module generates a separate Go schema package. The native adapter imports schemas and runtime; the application imports schemas, adapters, and runtime. Schemas never import adapters or application packages. Standard schemas belong to the pinned standard-library/runtime distribution. This prevents Go import cycles. An application contract over application Money types can have source implementations or explicitly wrap an adapter interface using data conversion, but cannot directly bind a separately compiled native adapter to application types.

Native receivers remain opaque. The host creates them and exposes contract views. Source fakes implement the interface contract for their own concrete type under ordinary coherence. The standard CLI host supplies only its enumerated roots; custom host construction still needs a concrete contract.

## Manifest version 1

The manifest is UTF-8 TOML with closed fields; unknown keys, duplicate bindings, unsupported versions, missing fields, and signature mismatches are compile errors.

```toml
format = 1
interface = "./files.ms"
go_package = "example.org/nativefiles"
go_version = "v1.0.0"
go_checksum = "h1:example-content-checksum"

[[bindings]]
contract = "Files"
operation = "open"
symbol = "Open"
effects = ["read", "external-call"]
cancellation = "cooperative"
acquisition = "dispose-undelivered"
disposer = "DisposeFile"
```

This is a schema example; its package and checksum are placeholders. Interface paths resolve relative to the manifest, and the Go fields pin the native package.

| Binding field | Rule |
| --- | --- |
| `contract`, `operation`, `symbol` | Select an exported interface/standard contract operation and an exported Go symbol; bind each operation exactly once |
| `effects` | Explicit subset of `read`, `write`, `external-call`, and `unknown`; use `[]` for an empty summary |
| `cancellation` | `cooperative`, `completion-only`, or `nonblocking` |
| `acquisition` | `none` or `dispose-undelivered` |
| `disposer` | Required exported symbol for `dispose-undelivered`; forbidden for `none` |

Resource bindings include a matching close operation. All native receivers, results, and retained callback environments must be immutable or synchronize mutable state and lifecycle. This is a mandatory adapter obligation; there is no opt-out via a plain view. Wrapping an unsafe receiver in Synchronized does not make escaped aliases safe.

## Generated bindings

Interface declarations determine parameter labels/order and result types; manifests do not duplicate them. Each Go operation receives the hidden execution context, opaque receiver, and generated parameters in declaration order, then returns the generated exact result type.

A disposer receives a shielded context and the acquired generated resource value. It completes release before returning. The fixed constructor `New` accepts runtime `HostInputs` and returns an opaque receiver token. Standard host packages follow the same convention.

The concrete Go declarations for `HostInputs`, receiver tokens, results, and disposers still need a pinned runtime ABI. Symbol/type mismatches must fail validation before linking; referring to an ABI alone does not define those declarations.

Wrappers enforce the [foreign value invariants](value-conversion.md). Disposal of an undelivered acquisition finishes before unwind, and no wrapper returns with outstanding foreign work. Native code requires separate cancellation, sharing, conversion, and release tests.

Acceptance requires a minimal interface/native-adapter/application fixture whose Go builds without cycles, rejection of interface imports from the application, source fake implementations, and invalid-value/acquisition race fixtures.
