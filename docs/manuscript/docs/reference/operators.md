---
title: "Operators"
linkTitle: "Operators"

description: >
  Complete reference for all operators in manuscript with precedence and examples.
---

manuscript provides a comprehensive set of operators for arithmetic, comparison, logical operations, and more.

## Arithmetic Operators

| Operator | Description | Example | Result |
|----------|-------------|---------|--------|
| `+` | Addition | `5 + 3` | `8` |
| `-` | Subtraction | `5 - 3` | `2` |
| `*` | Multiplication | `5 * 3` | `15` |
| `/` | Division | `15 / 3` | `5` |
| `%` | Modulo | `7 % 3` | `1` |
| `-` | Unary minus | `-5` | `-5` |
| `+` | Unary plus | `+5` | `5` |

### Examples
```ms
let a = 10
let b = 3

let sum = a + b        // 13
let diff = a - b       // 7
let product = a * b    // 30
let quotient = a / b   // 3
let remainder = a % b  // 1
```

## Comparison Operators

| Operator | Description | Example | Result |
|----------|-------------|---------|--------|
| `==` | Equal | `5 == 5` | `true` |
| `!=` | Not equal | `5 != 3` | `true` |
| `<` | Less than | `3 < 5` | `true` |
| `<=` | Less than or equal | `5 <= 5` | `true` |
| `>` | Greater than | `5 > 3` | `true` |
| `>=` | Greater than or equal | `5 >= 5` | `true` |

### Examples
```ms
let age = 25

if age >= 18 {
  print("Adult")
}

if age == 25 {
  print("Quarter century")
}

if age != 30 {
  print("Not thirty")
}
```

### Operator Chaining

manuscript supports chaining comparison operators, which is interpreted as a logical AND of the individual comparisons:

```ms
// Chained comparisons
let x = 5
let y = 10  
let z = 15

if x < y < z {
  // Equivalent to: (x < y) && (y < z)
  print("Values are in ascending order")
}

if 0 <= score <= 100 {
  // Equivalent to: (0 <= score) && (score <= 100)
  print("Valid score range")
}

// Works with any comparison operators
if a >= b >= c {
  // Equivalent to: (a >= b) && (b >= c)
  print("Descending order")
}
```

This makes mathematical expressions more readable and intuitive, especially for range checks.

## Logical Operators

| Operator | Description | Example | Result |
|----------|-------------|---------|--------|
| `&&` | Logical AND | `true && false` | `false` |
| `\|\|` | Logical OR | `true \|\| false` | `true` |
| `!` | Logical NOT | `!true` | `false` |

### Examples
```ms
let isAdult = age >= 18
let hasLicense = true

if isAdult && hasLicense {
  print("Can drive")
}

if isAdult || hasGuardian {
  print("Can enter")
}

if !isMinor {
  print("Not a minor")
}
```

## Assignment Operators

| Operator | Description | Example | Equivalent |
|----------|-------------|---------|------------|
| `=` | Assignment | `x = 5` | `x = 5` |
| `+=` | Add assign | `x += 3` | `x = x + 3` |
| `-=` | Subtract assign | `x -= 3` | `x = x - 3` |
| `*=` | Multiply assign | `x *= 3` | `x = x * 3` |
| `/=` | Divide assign | `x /= 3` | `x = x / 3` |
| `%=` | Modulo assign | `x %= 3` | `x = x % 3` |

### Examples
```ms
let count = 10

count += 5    // count is now 15
count -= 3    // count is now 12
count *= 2    // count is now 24
count /= 4    // count is now 6
count %= 4    // count is now 2
```

## String Operators

| Operator | Description | Example | Result |
|----------|-------------|---------|--------|
| `+` | Concatenation | `"Hello" + " World"` | `"Hello World"` |
| `+=` | Append | `str += "!"` | Appends to string |

### Examples
```ms
let greeting = "Hello"
let name = "Alice"

let message = greeting + ", " + name + "!"  // "Hello, Alice!"

greeting += " there"  // greeting is now "Hello there"
```

## Collection Operators

### Array Access
```ms
let numbers = [1, 2, 3, 4, 5]
let first = numbers[0]    // 1
let last = numbers[4]     // 5
```

### Object Access
```ms
let person = { name: "Alice", age: 30 }
let name = person.name         // "Alice" (dot notation)
let age = person["age"]        // 30 (bracket notation)
```

### Map Access
```ms
let scores = ["Alice": 95, "Bob": 87]
let aliceScore = scores["Alice"]  // 95
```

## Type Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `typeof` | Get type | `typeof(value)` |
| `as` | Type assertion | `value as string` |
| `!` | Bang type (error) | `(fn() int)!` |

### Examples
```ms
let value any = "hello"
let typeName = typeof(value)  // "string"

if typeof(value) == "string" {
  let text = value as string
  print(text.upper())
}
```

## Range Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `..` | Inclusive range | `1..5` (1, 2, 3, 4, 5) |
| `...` | Exclusive range | `1...5` (1, 2, 3, 4) |

### Examples
```ms
// In match expressions
match score {
  90..100: "A"
  80..89: "B"
  70..79: "C"
  default: "F"
}

// In for loops
for i in 1..10 {
  print(i)  // prints 1 through 10
}
```

## Special Operators

### Error Operators
```ms
// Try operator
let result = try parseNumber("42")

// Error creation (return keyword is optional)
error("something went wrong")

// Check operator
check value > 0
```

**Note:** The `return` keyword is optional in manuscript. Functions automatically return the value of the last expression. For example:

```ms
fn add(a int, b int) int {
  a + b  // automatically returned
}

fn greet(name string) string {
  "Hello, " + name  // automatically returned
}
```

### Collection Operators
```ms
// In operator (for iteration)
for item in collection {
  print(item)
}

// Spread operator (future feature)
let combined = [...array1, ...array2]
```

## Operator Precedence

From highest to lowest precedence:

1. **Primary** - `()`, `[]`, `.`, function calls
2. **Unary** - `!`, `-`, `+`, `typeof`
3. **Multiplicative** - `*`, `/`, `%`
4. **Additive** - `+`, `-`
5. **Relational** - `<`, `<=`, `>`, `>=`
6. **Equality** - `==`, `!=`
7. **Logical AND** - `&&`
8. **Logical OR** - `||`
9. **Assignment** - `=`, `+=`, `-=`, etc.

### Examples
```ms
// Precedence affects evaluation order
let result = 2 + 3 * 4    // 14 (not 20)
let result2 = (2 + 3) * 4 // 20

// Boolean operations
let result3 = true || false && false  // true (AND before OR)
let result4 = (true || false) && false // false
```

## Associativity

Most operators are left-associative:

```ms
let result = 10 - 5 - 2   // (10 - 5) - 2 = 3
let chain = a.b.c.d       // ((a.b).c).d
```

Assignment operators are right-associative:

```ms
let a, b, c = 0
a = b = c = 5  // c = 5, then b = c, then a = b
```

## Short-Circuit Evaluation

Logical operators use short-circuit evaluation:

```ms
// && stops at first false
if user != null && user.isActive() {
  // user.isActive() only called if user != null
}

// || stops at first true  
let name = user.name || "Unknown"
// "Unknown" only used if user.name is falsy
``` 