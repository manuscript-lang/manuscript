---
title: "Functions"
linkTitle: "Functions"
weight: 20
description: >
  Learn how to define and use functions in Manuscript.
---

# Functions

Learn how to define and use functions in Manuscript.

## Function Declaration

Basic function syntax:

```ms
func greet(name: string) -> string {
  return "Hello, " + name + "!"
}

func add(a: int, b: int) -> int {
  return a + b
}
```

## Function Parameters

### Default Parameters

```ms
func greet(name: string = "World") -> string {
  return "Hello, " + name + "!"
}

// Usage
greet()         // "Hello, World!"
greet("Alice")  // "Hello, Alice!"
```

### Multiple Parameters

```ms
func calculate(x: int, y: int, operation: string) -> int {
  if operation == "add" {
    return x + y
  } else if operation == "subtract" {
    return x - y
  }
  return 0
}
```

## Return Values

### Single Return Value

```ms
func square(x: int) -> int {
  return x * x
}
```

### Multiple Return Values

```ms
func divMod(a: int, b: int) -> (int, int) {
  return (a / b, a % b)
}

// Usage
let (quotient, remainder) = divMod(10, 3)
```

## Higher-Order Functions

Functions can accept other functions as parameters:

```ms
func apply(x: int, fn: (int) -> int) -> int {
  return fn(x)
}

func double(x: int) -> int {
  return x * 2
}

let result = apply(5, double)  // result = 10
``` 