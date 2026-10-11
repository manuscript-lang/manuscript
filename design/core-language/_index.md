+++
title = "Core language"
weight = 2
+++

# Manuscript core language guide

[Design index](../_index.md)

This guide introduces Manuscript's core language one concept at a time. Start with source structure and local values, then build domain types, write functions, choose control flow, and handle failures. Each concept has its own page with examples and links to the rules it depends on.

The [source grammar](basics/grammar.md), [expression and operator rules](basics/expressions.md), and [type compatibility](types/compatibility.md) define the accepted language. Concept pages explain declarations, inference, operation selection, and control flow. [Core conformance fixtures](../compiler/conformance/core-language.md) collect complete modules and expected outcomes.

## Reading order

### 1. [Language basics](basics/_index.md)

- [Source structure and syntax](basics/syntax.md)
- [Source grammar](basics/grammar.md)
- [Expressions and operators](basics/expressions.md)
- [Bindings and scope](basics/bindings.md)
- [Destructuring bindings](basics/destructuring.md)
- [Numbers and booleans](basics/numbers-and-booleans.md)
- [Strings and bytes](basics/text-and-bytes.md)

### 2. [Types and data modeling](types/_index.md)

- [Records and nominal types](types/records.md)
- [Alternatives](types/alternatives.md)
- [Optional values](types/optionals.md)
- [Collections](types/collections.md)
- [Equality and hashing](types/equality-and-hashing.md)
- [Operation contracts](types/contracts.md)
- [Generics and bounds](types/generics.md)
- [Type compatibility and expected types](types/compatibility.md)

### 3. [Functions](functions/_index.md)

- [Declarations and calls](functions/declarations-and-calls.md)
- [Function values and closures](functions/function-values-and-closures.md)

### 4. [Control flow](control-flow/_index.md)

- [Conditionals](control-flow/conditionals.md)
- [Loops](control-flow/loops.md)
- [Pattern matching](control-flow/pattern-matching.md)

### 5. [Errors and validation](errors/_index.md)

- [Expected failures with Result](errors/results.md)
- [Error propagation with try](errors/propagation.md)
- [Assertions and programming faults](errors/faults.md)

## Resources, concurrency, and boundaries

The core language works together with these design contracts:

| Continue with | When you need it |
| --- | --- |
| [Resource lifetimes and cleanup](../ownership-and-cleanup/_index.md) | Ordinary references, `with`, closed-state checks, and leaving scopes |
| [Concurrency](../concurrency/_index.md) | Parallel operations, background services, cancellation, and deadlines |
| [Modules and capabilities](../modules-and-capabilities/_index.md) | Exports, imports, external authority, and operation boundaries |
| [Standard library](../standard-library/_index.md) | Built-in types, collections, resources, and application hosts |
| [Compiler design](../compiler/_index.md) | Type, scope, and capture checking, and Go lowering |
| [Developer tooling](../developer-tooling/_index.md) | Formatting, diagnostics, diagrams, and debugging |
