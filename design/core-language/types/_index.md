+++
title = "Types and data modeling"
weight = 11
+++

# Types and data modeling

[Core language guide](../_index.md) · [Design index](../../_index.md)

`type` declares records or alternatives; `interface` declares an operation contract. A declaration uses exactly one form. Choose fields for domain data, alternatives for a set of possibilities, and an operation contract for required behavior.

Core and standard types also include `Unit`, whose only value is `unit`, and `Never`, which has no possible value. See [function returns](../functions/declarations-and-calls.md#unit-and-never) for their control-flow rules and the [standard type catalog](../../standard-library/types/catalog.md) for the full list.

| Concept | What you will learn |
| --- | --- |
| [Records and nominal types](records.md) | Declare immutable fields and distinguish domain identifiers. |
| [Alternatives](alternatives.md) | Represent a fixed set of possibilities with tagged cases. |
| [Optional values](optionals.md) | Represent absence explicitly with some and none. |
| [Collections](collections.md) | Use immutable lists, maps, and sets with eligible elements. |
| [Equality and hashing](equality-and-hashing.md) | Understand value comparison and key eligibility. |
| [Operation contracts](contracts.md) | Implement interfaces with concrete or generic blocks and choose plain or shared views. |
| [Generics and bounds](generics.md) | Apply parameterized types and express required properties. |
| [Type compatibility and expected types](compatibility.md) | Check exact types, contextual constructors, and inference boundaries. |
