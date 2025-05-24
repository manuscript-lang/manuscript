---
title: "Keywords"
linkTitle: "Keywords" 
weight: 20
description: >
  All reserved words and keywords in manuscript with usage examples.
---

This page lists all reserved keywords in the manuscript programming language.

## Language Keywords

### Core Keywords

| Keyword | Purpose | Example |
|---------|---------|---------|
| `fn` | Function declaration | `fn add(a int, b int) int { ... }` |
| `let` | Variable declaration | `let name = "Alice"` |
| `type` | Type definition | `type User { name string }` |
| `interface` | Interface definition | `interface Drawable { draw() }` |
| `methods` | Method implementation | `methods Rectangle as Drawable { ... }` |
| `as` | Type assertion/implementation | `methods Type as Interface` |
| `extends` | Type extension | `type Employee extends Person` |

### Control Flow

| Keyword | Purpose | Example |
|---------|---------|---------|
| `if` | Conditional statement | `if age >= 18 { ... }` |
| `else` | Alternative branch | `if condition { ... } else { ... }` |
| `for` | Loop statement | `for item in items { ... }` |
| `while` | While loop | `while condition { ... }` |
| `match` | Pattern matching | `match value { ... }` |
| `return` | Return from function (optional) | `result` |
| `break` | Exit loop | `break` |
| `continue` | Continue loop | `continue` |

### Error Handling

| Keyword | Purpose | Example |
|---------|---------|---------|
| `try` | Try expression | `let result = try parseNumber(text)` |
| `error` | Create error | `error("invalid input")` |
| `check` | Check condition | `check value > 0` |
| `defer` | Deferred execution | `defer file.close()` |

### Module System

| Keyword | Purpose | Example |
|---------|---------|---------|
| `import` | Import module | `import { add } from 'math.ms'` |
| `export` | Export declaration | `export fn add() { ... }` |
| `extern` | External dependency | `extern http from 'net/http'` |
| `from` | Import source | `import { fn } from 'module'` |

### Literals and Values

| Keyword | Purpose | Example |
|---------|---------|---------|
| `true` | Boolean true | `let active = true` |
| `false` | Boolean false | `let inactive = false` |
| `null` | Null value | `let empty = null` |
| `void` | Void value | `let nothing = void` |

### Advanced Features

| Keyword | Purpose | Example |
|---------|---------|---------|
| `yield` | Generator yield | `yield value` |
| `default` | Default case | `match x { default: ... }` |
| `typeof` | Type checking | `typeof(value) == "string"` |
| `in` | Collection iteration | `for item in collection` |

## Reserved for Future Use

These keywords are reserved and may be used in future versions:

- `const` - Constant declarations
- `var` - Alternative variable declaration  
- `class` - Class definitions
- `struct` - Structure definitions
- `enum` - Enumeration types
- `async` - Asynchronous functions
- `await` - Await async operations
- `where` - Generic constraints
- `when` - Conditional compilation
- `with` - Context managers

## Contextual Keywords

Some keywords are only reserved in specific contexts:

- `catch` - Only in try expressions: `try operation() catch defaultValue`
- `this` - Only in method implementations
- `super` - Only in extended types

## Naming Rules

### Valid Identifiers
- Must start with letter or underscore
- Can contain letters, digits, and underscores
- Cannot be a reserved keyword

### Examples
```ms
// Valid identifiers
let userName = "alice"
let _private = true
let count2 = 42
let MAX_SIZE = 100

// Invalid identifiers (keywords)
// let fn = "invalid"     // 'fn' is reserved
// let if = true          // 'if' is reserved
// let 123name = "bad"    // cannot start with digit
```

## Case Sensitivity

manuscript is case-sensitive. Keywords must be in lowercase:

```ms
// Correct
fn main() { ... }

// Incorrect  
Fn Main() { ... }  // Fn and Main are not keywords
FN MAIN() { ... }  // FN and MAIN are not keywords
``` 