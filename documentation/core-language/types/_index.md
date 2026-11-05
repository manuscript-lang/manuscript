+++
title = "Types"
weight = 3
+++

# Types

A type describes which values a program can hold and which operations make sense for them. Start by modeling data: records group fields, enums distinguish cases, and collections hold several values. Optional values make absence explicit. Then learn ownership before combining values into larger models. Interfaces describe shared behavior, and generics reuse a model or calculation while preserving its concrete types.

The chapters include examples to build on and precise rules to return to. Use the compatibility chapter when an assignment or call fails to type-check; it explains why a value does or does not fit an expected type.

| Concept | What you will learn |
| --- | --- |
| [Records and nominal types](records.md) | Declare mutable fields and distinguish domain identifiers. |
| [Enums](alternatives.md) | Represent a fixed set of possibilities with tagged cases. |
| [Collections](collections.md) | Use mutable lists, maps, and sets with explicit deep copies. |
| [Optional values](optionals.md) | Represent absence explicitly with T? and none. |
| [Mutation and references](references.md) | Understand moves, borrows, reassignment, and deep copies. |
| [Destructuring bindings](destructuring.md) | Unpack list positions and record fields. |
| [Interfaces and implementations](contracts.md) | Implement interfaces with concrete or generic blocks and pass concrete values where an interface is expected. |
| [Equality and hashing](equality-and-hashing.md) | Understand value comparison and key eligibility. |
| [Generics and bounds](generics.md) | Apply parameterized types and express required properties. |
| [Type compatibility and expected types](compatibility.md) | Check exact types, contextual constructors, and inference boundaries. |
