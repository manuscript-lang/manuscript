---
title: "Variables"
linkTitle: "Variables"
weight: 10
description: >
  Variable declarations, type annotations, and the manuscript type system.
---

Variables in manuscript are declared using the `let` keyword. manuscript supports type inference, explicit type annotations, and various declaration patterns.

## Basic Variable Declaration

### Simple Variables
```ms
let name = "Alice"        // string (inferred)
let age = 25              // int (inferred)
let height = 5.9          // float (inferred)
let active = true         // bool (inferred)
```

### With Type Annotations
```ms
let name string = "Alice"
let age int = 25
let height float = 5.9
let active bool = true
```

### Uninitialized Variables
```ms
let x int                 // declared but not initialized
let y                     // untyped, uninitialized
```

## Number Literals

manuscript supports various number formats:

```ms
let decimal = 42          // decimal integer
let binary = 0b1010       // binary: 10 in decimal
let hex = 0xFF            // hexadecimal: 255 in decimal
let octal = 0o755         // octal: 493 in decimal
let pi = 3.14159          // floating point
```

## String Literals

manuscript provides multiple string literal formats:

### Single Quotes
```ms
let message = 'Hello, World!'
let path = 'C:\Users\alice'
```

### Double Quotes
```ms
let message = "Hello, World!"
let template = "Welcome, ${name}!"
```

### Multi-line Strings
```ms
let poem = '''
Roses are red,
Violets are blue,
manuscript is clean,
And readable too.
'''

let config = """
{
  "name": "manuscript",
  "version": "0.1.0"
}
"""
```

### String Interpolation
```ms
let name = "Alice"
let age = 25
let greeting = "Hello, ${name}! You are ${age} years old."
```

## Special Values

```ms
let empty = null          // null value
let nothing = void        // void value
```

## Block Variable Declarations

You can declare multiple variables in a block:

```ms
let (
  name = "Alice"
  age = 25
  city = "New York"
)
```

### Mixed Types in Block
```ms
let (
  count int = 0
  message string = "Starting..."
  ready bool = false
)
```

## Destructuring Assignment

### Object Destructuring
```ms
let person = { name: "Alice", age: 25 }
let { name, age } = person
```

### Array Destructuring
```ms
let coordinates = [10, 20]
let [x, y] = coordinates
```

### Block Destructuring
```ms
let (
  { name, age } = getPerson()
  [x, y] = getCoordinates()
)
```

## Type System

### Basic Types
- `int` - integers
- `float` - floating point numbers
- `string` - text strings
- `bool` - boolean values (true/false)

### Collection Types
- `string[]` - array of strings
- `int[]` - array of integers
- `CustomType[]` - array of custom types

### Type Inference
manuscript infers types when possible:

```ms
let count = 42           // inferred as int
let message = "hello"    // inferred as string
let items = [1, 2, 3]    // inferred as int[]
```

### Explicit Types
Use explicit types when inference isn't sufficient:

```ms
let numbers int[] = []   // empty array needs explicit type
let result = null        // might need type annotation
```

## Variable Scope

Variables are scoped to their declaration block:

```ms
fn main() {
  let outer = "visible everywhere"
  
  if true {
    let inner = "only visible here"
    print(outer)  // works - outer scope
    print(inner)  // works - current scope
  }
  
  // print(inner)  // error - inner not accessible
}
```

## Naming Conventions

Follow these naming conventions:

- **Variables**: camelCase (`userName`, `totalCount`)
- **Constants**: UPPER_CASE (`MAX_SIZE`, `DEFAULT_TIMEOUT`)
- **Booleans**: descriptive names (`isActive`, `hasPermission`)

## Examples

### Configuration Variables
```ms
let (
  apiUrl string = "https://api.example.com"
  timeout int = 5000
  retries int = 3
  debug bool = false
)
```

### Processing Data
```ms
let input = "Hello, World!"
let length = input.length()
let uppercase = input.upper()
let words = input.split(" ")
```

### Working with Numbers
```ms
let price = 19.99
let tax = 0.08
let total = price * (1.0 + tax)
let rounded = round(total)
``` 