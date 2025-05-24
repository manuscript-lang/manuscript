---
title: "Beginner Guide"
linkTitle: "Beginner"
weight: 10
description: >
  Learn the fundamental concepts of Manuscript programming. Perfect for new programmers or those new to Manuscript.
---

Welcome to the Beginner Guide! This section covers all the fundamental concepts you need to start programming effectively in Manuscript. Whether you're new to programming or coming from another language, these guides will give you a solid foundation.

## What You'll Learn

By the end of this section, you'll understand:

- **Variables and Types** - How to store and work with data
- **Functions** - How to organize and reuse code
- **Control Flow** - How to make decisions and repeat actions
- **Data Structures** - How to work with collections of data

## Learning Path

Follow these guides in order for the best learning experience:

### 1. [Variables and Types](variables-and-types/)
Learn how to declare variables, understand different data types, and work with type inference.

```ms
let name = "Alice"        // string
let age = 25             // int
let height = 5.6         // float
let active = true        // bool
```

### 2. [Functions](functions/)
Master function definition, parameters, return values, and basic error handling.

```ms
fn greet(name string) {
  print("Hello, " + name + "!")
}

fn add(a int, b int) int {
  return a + b
}
```

### 3. [Control Flow](control-flow/)
Learn to control program execution with conditions, loops, and branching.

```ms
if age >= 18 {
  print("Adult")
} else {
  print("Minor")
}

for i = 1; i <= 10; i++ {
  print(i)
}
```

### 4. [Basic Data Structures](data-structures/)
Work with arrays, objects, and basic collections to organize your data.

```ms
let numbers = [1, 2, 3, 4, 5]
let person = {
  name: "Alice"
  age: 30
}
```

## Prerequisites

Before starting this guide, make sure you have:

- ✅ [Installed Manuscript](../getting-started/installation/)
- ✅ [Written your first program](../getting-started/first-program/)
- ✅ [Read the language overview](../getting-started/overview/)

## Learning Tips

### Practice as You Go
Each section includes examples you can run. Try modifying them to see what happens:

```ms
// Try changing these values and see what happens
let greeting = "Hello"
let name = "World"
print(greeting + ", " + name + "!")
```

### Experiment Freely
Don't be afraid to experiment! Create small programs to test your understanding:

```ms
fn main() {
  // Your experimental code here
  let x = 10
  let y = 20
  print("Sum: " + string(x + y))
}
```

### Build Something Real
After each section, try building a small project that uses what you've learned.

## Code Examples

All examples in this guide are tested and working. You can copy and run them directly:

```bash
# Save example to test.ms
echo 'fn main() {
  let message = "Learning Manuscript!"
  print(message)
}' > test.ms

# Run it
msc test.ms
```

## Getting Help

If you get stuck:

1. **Check the examples** - Each concept has working code examples
2. **Experiment** - Try variations to understand behavior
3. **Ask questions** - Use [GitHub Discussions](https://github.com/manuscript-co/manuscript/discussions)
4. **Read ahead** - Sometimes later sections clarify earlier concepts

## What's Next?

After completing the beginner guide:

- **[Intermediate Guide](../intermediate/)** - Advanced features and patterns
- **[Tutorials](../tutorials/)** - Build real applications
- **[Examples](../examples/)** - See practical code examples

## Quick Reference

### Variables
```ms
let name = "value"           // Declaration with value
let count int = 42          // Explicit type
let x, y = 10, 20          // Multiple variables
```

### Functions
```ms
fn functionName(param type) returnType {
  // function body
  return value
}
```

### Control Flow
```ms
if condition {
  // if block
} else {
  // else block
}

for init; condition; update {
  // loop body
}
```

### Collections
```ms
let array = [1, 2, 3]
let object = {key: "value"}
```

Ready to begin? Start with [Variables and Types](variables-and-types/)!

{{% alert title="Take Your Time" %}}
Programming is a skill that develops with practice. Don't rush through the material - make sure you understand each concept before moving on.
{{% /alert %}} 