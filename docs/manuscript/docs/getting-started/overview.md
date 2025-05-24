---
title: "Language Overview"
linkTitle: "Overview"
description: >
  Learn about manuscript's design philosophy, key features, and what makes it unique.
---

manuscript is a modern programming language designed for readability and AI-friendliness. It compiles to Go, giving you Go's performance and ecosystem while providing a cleaner, more expressive syntax.

## Design Philosophy

### Readability First

manuscript code should be immediately understandable:

```ms
fn calculateTax(income float, rate float) float {
  if income <= 0 {
    return 0.0
  }
  return income * rate
}
```

### Minimal Symbols

We prefer words over symbols whenever possible:

```ms
fn process(items string[]) string[] {
  let results = []
  for item in items {
    if item != null {
      results.append(item.upper())
    }
  }
  return results
}
```

### AI-Friendly Syntax

manuscript is designed to work well with AI code generation:

- Consistent patterns reduce ambiguity
- Clear keywords make intent obvious
- Minimal syntax variations reduce confusion
- Error messages tuned for clarity

## Key Features

### Type Safety with Inference

Strong typing catches errors at compile time, but you don't need to specify types everywhere:

```ms
let name = "Alice"           // Inferred as string
let age = 25                 // Inferred as int
let height = 5.6             // Inferred as float
let active = true            // Inferred as bool

// Explicit types when needed
let users User[] = []
let config Config = loadConfig()
```

### Built-in Error Handling

Error handling with the `!` syntax:

```ms
fn readFile(path string) string! {
  let content = try os.readFile(path)
  return content.trim()
}

fn main() {
  let content = try readFile("config.txt")
  print("Config: " + content)
}
```

### Go Performance

Compiles to efficient Go code:

```ms
// manuscript code
fn fibonacci(n int) int {
  if n <= 1 {
    return n
  }
  return fibonacci(n-1) + fibonacci(n-2)
}
```

Becomes idiomatic Go code with full performance.

## Language Constructs

### Variables and Types

```ms
// Basic types
let count int = 42
let message string = "Hello"
let active bool = true
let price float = 19.99

// Collections
let numbers = [1, 2, 3, 4]
let person = { name: "Alice", age: 30 }
let scores = ["Alice": 95, "Bob": 87]

// Custom types
type User {
  name string
  email string
  age int
}
```

### Functions

```ms
// Simple function
fn greet(name string) {
  print("Hello, " + name)
}

// With return type
fn add(a int, b int) int {
  return a + b
}

// Error handling
fn divide(a int, b int) float! {
  if b == 0 {
    return error("division by zero")
  }
  return float(a) / float(b)
}
```

### Control Flow

```ms
// Conditionals
if age >= 18 {
  print("Adult")
} else {
  print("Minor")
}

// Loops
for item in items {
  print(item)
}

for let i = 0; i < 10; i = i + 1 {
  print(i)
}

// Pattern matching
let grade = match score {
  90..100: "A"
  80..89: "B"
  70..79: "C"
  default: "F"
}
```

### Modules

```ms
// math.ms
export fn add(a int, b int) int {
  return a + b
}

// main.ms
import { add } from 'math.ms'

fn main() {
  let result = add(5, 3)
  print("Result: " + string(result))
}
```

## Compilation Model

manuscript follows a simple compilation process:

1. **Parse** - manuscript source code to AST
2. **Type Check** - Verify types and catch errors
3. **Generate** - Emit idiomatic Go code
4. **Compile** - Use Go compiler for final binary

This gives you:
- Fast compilation times
- Go's performance characteristics
- Access to Go's ecosystem
- Familiar deployment patterns

## Design Principles

**Clarity over Cleverness** - Code should be obvious in its intent.

**Consistent Patterns** - Similar concepts should look similar.

**Graceful Error Handling** - Errors should be explicit and manageable.

**Minimal Cognitive Load** - Reduce the mental overhead of reading code.

## Comparison with Go

manuscript improves on Go's syntax while maintaining its performance:

```go
// Go
func processUsers(users []User) []string {
    var names []string
    for _, user := range users {
        if user.Active {
            names = append(names, strings.ToUpper(user.Name))
        }
    }
    return names
}
```

```ms
// manuscript
fn processUsers(users User[]) string[] {
  let names = []
  for user in users {
    if user.active {
      names.append(user.name.upper())
    }
  }
  return names
}
```

## When to Use manuscript

**Good fit for:**
- New projects prioritizing readability
- Teams working with AI coding assistants
- Applications requiring Go's performance
- Code that needs to be maintained long-term

**Consider alternatives for:**
- Existing Go codebases (unless refactoring)
- Performance-critical systems (stick with Go directly)
- Projects requiring specific language features not yet in manuscript

## Next Steps

1. [Write your first program](../first-program/) - Get hands-on experience
2. [Explore language features](../../constructs/) - Learn the core constructs
3. [Check the reference](../../reference/) - Detailed syntax information

## Learning Resources

- **Examples** - See practical code in the language features section
- **Reference** - Complete syntax and grammar documentation
- **Community** - Join discussions on GitHub for help and feedback 