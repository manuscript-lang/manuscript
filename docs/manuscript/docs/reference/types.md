---
title: "Built-in Types"
linkTitle: "Types"
weight: 30
description: >
  Complete reference for all built-in types in manuscript.
---

manuscript provides a comprehensive type system with built-in primitive types, collection types, and type annotations.

## Primitive Types

### Numeric Types

| Type | Description | Size | Range | Example |
|------|-------------|------|-------|---------|
| `int` | Signed integer | 64-bit | -2^63 to 2^63-1 | `let count int = 42` |
| `float` | Floating point | 64-bit | IEEE 754 double | `let price float = 19.99` |

### Text Types

| Type | Description | Example |
|------|-------------|---------|
| `string` | UTF-8 text | `let name string = "Alice"` |
| `char` | Single character | `let initial char = 'A'` |

### Boolean Type

| Type | Description | Values | Example |
|------|-------------|--------|---------|
| `bool` | Boolean value | `true`, `false` | `let active bool = true` |

### Special Types

| Type | Description | Example |
|------|-------------|---------|
| `null` | Null value | `let empty = null` |
| `void` | Void/unit type | `let nothing = void` |
| `any` | Any type (dynamic) | `let value any = 42` |

## Collection Types

### Arrays

```ms
// Array type syntax
let numbers int[] = [1, 2, 3]
let names string[] = ["Alice", "Bob"]
let mixed any[] = [1, "hello", true]

// Empty arrays need explicit type
let empty int[] = []
```

### Objects

```ms
// Object with known structure
let person = { name: "Alice", age: 30 }

// Object type annotation
let user: { name: string, age: int, active: bool }
```

### Maps

```ms
// Map type syntax  
let scores map[string]int = ["Alice": 95, "Bob": 87]
let config map[string]string = ["host": "localhost"]

// Empty maps
let empty map[string]int = [:]
```

### Sets

```ms
// Set type syntax
let numbers set[int] = <1, 2, 3, 4>
let names set[string] = <"Alice", "Bob">

// Empty sets
let empty set[int] = <>
```

## Function Types

### Function Signatures

```ms
// Function type syntax
let operation (fn(int, int) int)

// Assigning functions
operation = fn(a int, b int) int {
  a + b  // return keyword optional
}
```

### Error-Returning Functions

```ms
// Bang function type
let parser (fn(string) int)!

parser = fn(text string) int! {
  if text == "" {
    error("empty string")
  }
  parseInt(text)
}
```

## Type Annotations

### Variable Declarations

```ms
// Explicit type annotation
let count int = 0
let message string = "hello"
let active bool = true

// Type inference (preferred when clear)
let count = 0        // inferred as int
let message = "hello" // inferred as string
let active = true    // inferred as bool
```

### Function Parameters and Returns

```ms
// Parameter types are required
fn process(data string, count int) bool {
  count > 0  // automatically returned
}

// Return type can be explicit or inferred
fn add(a int, b int) int {  // explicit return type
  a + b  // automatically returned
}

fn multiply(a int, b int) {  // inferred return type (int)
  a * b  // automatically returned
}
```

## Custom Types

### Type Definitions

```ms
// Simple type alias
type UserId = string
type Score = int

// Struct-like types
type User {
  id UserId
  name string
  email string
  score Score
}
```

### Optional Fields

```ms
type Product {
  name string
  price float
  description string?  // optional field
  tags string[]?       // optional array
}
```

## Union Types

```ms
// Union type syntax
type Status = "pending" | "completed" | "failed"
type Result = int | string | Error

// Using union types
fn processResult(result Result) {
  match typeof(result) {
    "int": print("Number: " + string(result))
    "string": print("Text: " + result)
    "Error": print("Error: " + result.message())
  }
}
```

## Generic Types

```ms
// Generic type parameters
type Container[T] {
  value T
  metadata map[string]string
}

// Using generic types
let stringContainer = Container[string]{
  value: "hello",
  metadata: ["type": "text"]
}

let numberContainer = Container[int]{
  value: 42,
  metadata: ["type": "number"]
}
```

## Type Checking

### Runtime Type Checking

```ms
// typeof operator
let value any = "hello"
let typeName = typeof(value)  // "string"

// Type checking in conditions
if typeof(value) == "string" {
  print("It's a string: " + value)
}
```

### Type Assertions

```ms
// Type assertion
let value any = "hello"
let text = value as string  // assert value is string

// Safe type assertion with checking
if typeof(value) == "string" {
  let text = value as string
  print(text.upper())
}
```

## Type Compatibility

### Assignment Compatibility

```ms
// Compatible assignments
let count int = 42
let score = count    // int to int (same type)

// Collection compatibility
let numbers = [1, 2, 3]      // int[]
let values int[] = numbers   // compatible

// Function compatibility
let add = fn(a int, b int) int { a + b }  // return keyword optional
let operation (fn(int, int) int) = add  // compatible
```

### Interface Compatibility

```ms
interface Drawable {
  draw() void
  getArea() float
}

type Rectangle {
  width float
  height float
}

// Rectangle becomes compatible with Drawable
// when methods are implemented
methods Rectangle as Drawable {
  draw() void { /* implementation */ }
  getArea() float { this.width * this.height }
}
```

## Type Conversion

### Explicit Conversion

```ms
// Numeric conversions
let i int = 42
let f float = float(i)    // int to float
let s string = string(i)  // int to string

// String conversions
let text string = "123"
let num int = parseInt(text)  // string to int (can fail)
```

### Implicit Conversion

manuscript has minimal implicit conversion for safety:

```ms
// These do NOT work (compile error)
// let f float = 42        // int to float needs explicit conversion
// let s string = 42       // int to string needs explicit conversion

// These DO work
let i = 42              // literal 42 can be int
let f = 42.0            // literal 42.0 can be float
let s = "hello"         // literal "hello" can be string
``` 