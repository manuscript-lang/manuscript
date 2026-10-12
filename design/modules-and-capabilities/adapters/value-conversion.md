+++
title = "Foreign values and the trust boundary"
weight = 84
+++

# Foreign values and the trust boundary

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

An adapter must validate foreign values before exposing them as Manuscript values. For example, a Go string may contain invalid UTF-8, while a Manuscript String may not. Conversion must preserve every guarantee of the source type.

Adapters validate UTF-8, alternative tags and payloads, required non-nil values, and numeric ranges. They preserve value and reference behavior and copy immutable byte buffers unless exclusive ownership can be established. Mutable collection storage stays behind checked collection operations; unrestricted Go interfaces and runtime task internals are not exposed to Manuscript source. Raw Go dependencies may use ambient authority, so source capability checking is not a sandbox for adapter code.

## Preserving invariants

A converted string must be valid UTF-8. An alternative must carry a valid tag. A buffer must not become mutable through a hidden Go alias after being exposed as immutable source data. Exclusive native buffer transfer is an optimization only when the adapter proves no mutable Go aliases remain; source code has no move or ownership checker.

An invalid foreign value is a programming fault with the operation, expected type, and value path in its diagnostic. It is not an expected input error: untrusted data should remain `Bytes` until explicitly decoded. The [manifest binding](manifests.md) defines wrapper validation and release obligations.

See [Go representations](../../compiler/lowering/value-representations.md) and [text and byte values](../../core-language/basics/text-and-bytes.md).

[Previous: Adapter manifests](../adapters/manifests.md) · [Next: Foreign cancellation and resource acquisition](../adapters/cancellation.md)
