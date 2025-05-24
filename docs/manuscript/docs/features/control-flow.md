---
title: "Control Flow"
linkTitle: "Control Flow"

description: >
  Conditional statements, loops, pattern matching, and flow control in manuscript.
---

manuscript provides several constructs for controlling program flow including conditionals, loops, pattern matching, and early exit statements.

## Conditional Statements

### If Statements
```ms
let age = 18

if age >= 18 {
  print("Adult")
}
```

### If-Else
```ms
let score = 85

if score >= 90 {
  print("A grade")
} else if score >= 80 {
  print("B grade")
} else if score >= 70 {
  print("C grade")
} else {
  print("Below C grade")
}
```

### Inline Conditionals
```ms
let status = if age >= 18 { "adult" } else { "minor" }
let message = if score > 85 { "Great job!" } else { "Keep trying!" }
```

## Loops

### For Loops

#### Traditional For Loop
```ms
for let i = 0; i < 10; i = i + 1 {
  print("Count: " + string(i))
}
```

#### For-In Loop (Arrays)
```ms
let numbers = [1, 2, 3, 4, 5]

for num in numbers {
  print("Number: " + string(num))
}
```

#### For-In Loop (Objects)
```ms
let person = { name: "Alice", age: 30, city: "New York" }

for key in person {
  print(key + ": " + string(person[key]))
}
```

#### For-In Loop with Index
```ms
let items = ["apple", "banana", "cherry"]

for i, item in items {
  print(string(i) + ": " + item)
}
```

### While Loops
```ms
let count = 0

while count < 5 {
  print("Count: " + string(count))
  count = count + 1
}
```

### Loop Control

#### Break Statement
```ms
for i in range(10) {
  if i == 5 {
    break
  }
  print(i)
}
// Prints: 0, 1, 2, 3, 4
```

#### Continue Statement
```ms
for i in range(10) {
  if i % 2 == 0 {
    continue
  }
  print(i)
}
// Prints: 1, 3, 5, 7, 9
```

## Pattern Matching

manuscript supports powerful pattern matching with `match` expressions:

### Basic Match
```ms
let value = 42

let result = match value {
  0: "zero"
  1: "one"
  42: "the answer"
  default: "unknown"
}
```

### Match with Conditions
```ms
let score = 85

let grade = match score {
  90..100: "A"
  80..89: "B"
  70..79: "C"
  60..69: "D"
  default: "F"
}
```

### Match with Types
```ms
fn processValue(value any) string {
  return match value {
    int: "integer: " + string(value)
    string: "text: " + value
    bool: "boolean: " + string(value)
    default: "unknown type"
  }
}
```

### Match with Destructuring
```ms
let point = { x: 10, y: 20 }

let description = match point {
  { x: 0, y: 0 }: "origin"
  { x: 0, y }: "on y-axis at " + string(y)
  { x, y: 0 }: "on x-axis at " + string(x)
  { x, y }: "point at (" + string(x) + "," + string(y) + ")"
}
```

### Match with Code Blocks
```ms
let status = "error"

match status {
  "success" {
    print("Operation completed successfully")
    updateProgress(100)
  }
  "error" {
    print("An error occurred")
    logError("Operation failed")
  }
  "pending" {
    print("Operation in progress")
    showSpinner()
  }
  default {
    print("Unknown status: " + status)
  }
}
```

## Try-Catch (Error Handling)

### Try Expressions
```ms
let result = try parseNumber("42")
// result contains the parsed number or error is propagated
```

### Try with Default
```ms
let result = try parseNumber("invalid") catch 0
// result = 0 if parsing fails
```

### Check Statements
```ms
fn processFile(filename string) {
  check fileExists(filename)  // exits function if false
  check isReadable(filename)  // exits function if false
  
  // Continue processing...
}
```

## Early Exit Statements

### Return
```ms
fn validateAge(age int) bool {
  if age < 0 {
    return false
  }
  
  if age > 150 {
    return false
  }
  
  return true
}
```

### Yield (for generators)
```ms
fn generateNumbers() {
  for i in range(5) {
    yield i * 2
  }
}
```

### Defer
```ms
fn processFile(filename string) {
  let file = openFile(filename)
  defer file.close()  // Always executed when function exits
  
  // Process file...
  // file.close() is automatically called
}
```

## Guard Clauses

Use guard clauses for early validation:

```ms
fn calculateDiscount(price float, customerType string) float! {
  // Guard clauses
  if price <= 0 {
    return error("price must be positive")
  }
  
  if customerType == "" {
    return error("customer type required")
  }
  
  // Main logic
  return match customerType {
    "premium": price * 0.15
    "regular": price * 0.10
    "new": price * 0.05
    default: 0.0
  }
}
```

## Nested Control Flow

You can combine different control flow constructs:

```ms
fn processData(items any[]) {
  for item in items {
    if item == null {
      continue
    }
    
    match typeof(item) {
      "string" {
        if item.length() > 0 {
          print("Processing string: " + item)
        }
      }
      "int" {
        if item > 0 {
          for i in range(item) {
            print("Step " + string(i))
          }
        }
      }
      default {
        print("Unknown type, skipping")
        continue
      }
    }
  }
}
```

## Best Practices

### Readability
- Use descriptive variable names in loops
- Prefer `for-in` loops over traditional `for` loops when possible
- Use guard clauses to reduce nesting

### Performance
- Use `break` and `continue` to avoid unnecessary iterations
- Consider using `match` instead of long `if-else` chains

### Error Handling
- Use `try` expressions for operations that might fail
- Use `defer` for cleanup operations
- Validate inputs early with guard clauses

### Pattern Matching
- Use `match` for complex conditional logic
- Leverage destructuring for cleaner data access
- Always include a `default` case for completeness 