+++
title = "Explicit capability authority"
weight = 80
+++

# Explicit capability authority

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A capability is how external authority reaches Manuscript code. Read capability parameters to identify the services an operation can access.

Capabilities represent external authority such as storage, network access, a clock, or a model client. They are explicit inputs. Manuscript source has no ambient application access to these services. Standard shareable capability implementations support concurrent calls; shared internal state must be synchronized. Resource methods also enforce closed state.

The language requires explicit authority inputs. Tooling still needs a precise classification rule for distinguishing a capability interface from a pure operation contract, including wrappers and function values that retain authority. Until that rule is settled, a diagram cannot claim to enumerate all reachable authority from parameter names alone.

## Sharing an implementation

A shareable network or storage implementation can receive concurrent calls. Its mutable internal state must be synchronized. References do not extend a resource's open lifetime; methods coordinate active calls with close.

Passing a capability explicitly makes the dependency visible to reviewers and compiler-derived diagrams. It also makes it possible to substitute controlled implementations when testing.

See [resource sharing](../../ownership-and-cleanup/values/sharing.md) and [the foreign-code trust boundary](../adapters/value-conversion.md).

[Previous: Boundary contracts](../modules/boundaries.md) · [Next: Inferred effects and call relationships](../capabilities/effects.md)
