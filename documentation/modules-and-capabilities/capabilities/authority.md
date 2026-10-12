+++
title = "Host services and capability values"
weight = 80
+++

# Host services and capability values

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A capability is an object that lets a function use an external service, such as storage, networking, a clock, or a model client. A helper can receive that object as an ordinary parameter, making its dependency visible and allowing tests to supply a source implementation.

Applications can also import host accessors such as `filesystem()`, `network()`, or `clock()` from their standard modules. They return the services associated with the current execution; [CLI hosts](../../standard-library/hosts/cli.md#importing-host-services) defines the complete accessor set and lifetime rules. Accessors do not require dependency declarations on the calling function. Importing a contract type alone does not obtain a service.

Manuscript does not enforce a per-function authority set or manifest permissions. Native host services provide their normal OS access. Explicit parameters are a composition and testing technique, rather than the only route to a service. Tooling cannot claim to enumerate all reachable authority from parameter names alone; callbacks and stored values can retain services as well.

## Sharing an implementation

A network or storage implementation can receive concurrent calls. Its mutable internal state must be synchronized. References do not extend a resource's open lifetime; methods coordinate active calls with close.

See [resource sharing](../../ownership-and-cleanup/values/sharing.md) and [the foreign-code trust boundary](../adapters/value-conversion.md).

[Previous: Boundary contracts](../modules/boundaries.md) · [Next: Inferred effects and call relationships](effects.md)
