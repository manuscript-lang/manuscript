---
title: "Your First Program"
linkTitle: "First Program"
description: >
  Write and run your first manuscript program step by step.
---

Let's write your first program in manuscript. This guide will walk you through creating, compiling, and running a simple manuscript program.

## Hello World

Every programming journey starts with "Hello, World!":

### Create the File
```bash
touch hello.ms
```

### Write the Code
```ms
fn main() {
  print("Hello, World!")
}
```

### Run the Program
```bash
msc hello.ms
```

Output:
```
Hello, World!
```

## Working with Variables

Let's expand our program to use variables:

```ms
fn main() {
  let name = "manuscript"
  let version = "0.1.0"
  
  print("Hello from " + name + " " + version + "!")
}
```

This introduces:
- `let` declarations for variables
- String concatenation with `+`
- Type inference (types are automatically determined)

## Numbers and Math

manuscript handles different types of data:

```ms
fn main() {
  let x = 10
  let y = 20
  let sum = x + y
  
  print("The sum of " + string(x) + " and " + string(y) + " is " + string(sum))
}
```

New concepts:
- Integer variables
- Mathematical operations
- Type conversion with `string()`

## Functions

Let's create our own function:

```ms
fn greet(name string) {
  print("Hello, " + name + "!")
}

fn main() {
  greet("Alice")
  greet("Bob")
  greet("Charlie")
}
```

This shows:
- Function definition with `fn`
- Parameter types (`string`)
- Function calls from `main()`

## Functions with Return Values

Functions can return values:

```ms
fn add(a int, b int) int {
  return a + b
}

fn main() {
  let result = add(5, 3)
  print("5 + 3 = " + string(result))
}
```

Key points:
- Return type specified after parameters (`int`)
- `return` statement
- Using returned value in variables

## Error Handling

manuscript has built-in error handling with bang functions:

```ms
fn divide(a int, b int) int! {
  if b == 0 {
    return error("Cannot divide by zero")
  }
  return a / b
}

fn main() {
  let result = try divide(10, 2)
  print("Result: " + string(result))
  
  let errorResult = try divide(10, 0)
  // Error is handled by try expression
}
```

This introduces:
- Bang functions (`int!`) for error handling
- `if` statements for conditions
- `try` expressions for error handling
- `error()` function to create errors

## Data Structures

manuscript provides arrays and objects:

```ms
fn main() {
  let numbers = [1, 2, 3, 4, 5]
  let person = { name: "Alice", age: 30 }
  
  print("First number: " + string(numbers[0]))
  print("Person name: " + person.name)
  print("Person age: " + string(person.age))
}
```

This shows:
- Array literals `[1, 2, 3]`
- Object literals `{ key: value }`
- Array indexing `numbers[0]`
- Object field access `person.name`

## String Interpolation

manuscript supports string interpolation:

```ms
fn main() {
  let name = "World"
  let count = 42
  print("Hello, ${name}! Count: ${count}")
}
```

## Block Variable Declarations

You can declare multiple variables at once:

```ms
fn main() {
  let (
    name = "manuscript"
    version = "0.1.0"
    stable = false
  )
  
  print("${name} v${version} - Stable: ${stable}")
}
```

## Next Steps

Now that you've written your first programs, you're ready to:

1. [Learn the language overview](../overview/) - Understand manuscript's philosophy
2. [Explore language features](../../constructs/) - Deep dive into language constructs
3. [Read the reference](../../reference/) - Complete syntax documentation

## Common Patterns

Here are patterns you'll use frequently:

### Working with Collections
```ms
fn main() {
  let items = ["apple", "banana", "cherry"]
  
  for item in items {
    print("Item: " + item)
  }
}
```

### Error Handling Pattern
```ms
fn processData(input string) string! {
  if input == "" {
    return error("input cannot be empty")
  }
  
  return input.upper()
}

fn main() {
  let result = try processData("hello")
  print("Processed: " + result)
}
```

### Type Definitions
```ms
type Person {
  name string
  age int
}

fn main() {
  let alice = Person{
    name: "Alice",
    age: 30
  }
  
  print("Name: " + alice.name)
}
```

Keep experimenting with these concepts. The best way to learn manuscript is by writing code! 