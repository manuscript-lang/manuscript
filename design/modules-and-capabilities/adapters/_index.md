+++
title = "Foreign adapter contracts"
weight = 82
+++

# Foreign adapter contracts

[Guide index](../_index.md) · [Design index](../../_index.md)

Adapters connect Manuscript code to foreign implementations such as Go. These design contracts explain how an adapter declares its API, validates values, and cooperates with cancellation and cleanup. Check implementation coverage before relying on external adapters.

- [Adapter manifests](manifests.md) — Declare a foreign adapter API and the facts the compiler trusts.
- [Foreign values and the trust boundary](value-conversion.md) — Validate foreign values before they enter Manuscript.
- [Foreign cancellation and resource acquisition](cancellation.md) — Arrange for foreign calls and resource acquisition to respond to stopping.
