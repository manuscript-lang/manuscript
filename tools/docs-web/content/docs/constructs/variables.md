---
title: "Variables and Types"
linkTitle: "Variables"
weight: 10
description: >
  Learn how to declare variables and work with Manuscript's type system.
---

# Variables and Types

Learn how to declare variables and work with Manuscript's type system.

## Variable Declaration

Manuscript supports both explicit and implicit variable declarations:

```ms
// Explicit type declaration
let name: string = "John"
let age: int = 30
let height: float = 5.9

// Type inference
let city = "New York"  // inferred as string
let population = 8_000_000  // inferred as int
let temperature = 72.5  // inferred as float
```

## Basic Types

### Primitive Types

- `int` - Integer numbers
- `float` - Floating-point numbers
- `string` - Text strings
- `bool` - Boolean values (`true` or `false`)

### Example Usage

```ms
let count: int = 42
let pi: float = 3.14159
let message: string = "Hello, Manuscript!"
let isReady: bool = true
```

## Mutability

Variables are immutable by default. Use `var` for mutable variables:

```ms
let x = 10        // immutable
// x = 20         // Error: cannot assign to immutable variable

var y = 10        // mutable
y = 20            // OK
```

## Constants

Use `const` for compile-time constants:

```ms
const MAX_SIZE = 1000
const VERSION = "1.0.0"
``` 