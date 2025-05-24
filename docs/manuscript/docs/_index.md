---
title: "Docs"
linkTitle: "Learn manuscript"

---
manuscript is a modern programming language that compiles to Go, designed for readability and simplicity.

## Quick Example

```ms
fn main() {
  let message = "Hello, World!"
  print(message)
}
```

## Docs Sections

### [Getting Started](getting-started/)
Installation, first program, and language overview. Start here if you're new to manuscript.

### [Language Features](constructs/)
Complete guide to all language constructs:
- Variables and type system
- Functions and closures
- Control flow and pattern matching
- Data structures and collections
- Modules and imports
- Error handling

### [Language Reference](reference/)
Technical reference for syntax, grammar, built-in types, and standard library.

## Key Design Principles

**Readability First** - Code should be immediately understandable with minimal symbols.

**Type Safety** - Strong typing catches errors at compile time with helpful inference.

**Go Integration** - Compiles to efficient Go code, accessing Go's ecosystem and performance.

**AI-Friendly** - Syntax designed for clarity in AI code generation and understanding.

## Language Overview

### Variables and Types
```ms
let name = "Alice"        // string (inferred)
let age int = 25          // explicit type
let active = true         // bool (inferred)
```
### Functions
```ms
fn greet(name string) string {
  return "Hello, " + name
}
```

### Error Handling
```ms
fn divide(a int, b int) int! {
  if b == 0 {
    return error("division by zero")
  }
  return a / b
}
```

### Control Flow
```ms
if age >= 18 {
  print("Adult")
} else {
  print("Minor")
}

for item in items {
  print(item)
}
```

### Data Structures
```ms
let numbers = [1, 2, 3, 4]
let person = { name: "Alice", age: 30 }
let scores = ["Alice": 95, "Bob": 87]
```

## Next Steps

1. [Install manuscript](getting-started/installation/) and set up your environment
2. [Write your first program](getting-started/first-program/) 
3. [Explore language constructs](constructs/) to learn core features
4. [Reference documentation](reference/) for detailed syntax information 
