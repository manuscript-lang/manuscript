---
title: "Functions"
linkTitle: "Functions"

description: >
  Function definitions, parameters, return types, and error handling in manuscript.
---

Functions: the trusty workhorses of your code! Got a job that needs doing? Package it up in a function, give it a name, and call it whenever you need. It's like having a magical spellbook for your program!

**Note:** The `return` keyword is optional in manuscript. Functions automatically return the value of the last expression. That's right, Manuscript is so chill, even `return` is often optional. The last expression? That's your return ticket!

## Basic Function Declaration

Code block takes a task,
Call its name, it does the work,
Magic, clean, and neat.

### Simple Function
```ms
fn greet() {
  print("Hello, World!")
}
```

### Function with Parameters
```ms
fn greet(name string) {
  print("Hello, " + name + "!")
}
```

### Function with Return Type
```ms
fn add(a int, b int) int {
  a + b  // automatically returned
}
```

## Parameters

### Required Parameters
```ms
fn calculateArea(width float, height float) float {
  width * height  // automatically returned
}
```

### Default Parameters
Sometimes, you're just not feeling picky. Default parameters are for those easy-going moments.
```ms
fn greet(name string, greeting string = "Hello") {
  print(greeting + ", " + name + "!")
}

// Usage
greet("Alice")              // uses default greeting
greet("Bob", "Hi")          // custom greeting
```

### Multiple Parameters
```ms
fn createUser(name string, age int, email string, active bool) {
  // function body
}
```

## Return Values

### Single Return Value
```ms
fn double(x int) int {
  x * 2  // automatically returned
}
```

### Multiple Return Values
Why return one thing when you can return two? Or three? Or... well, let's not get carried away. But Manuscript lets you bundle them up!
```ms
fn divideWithRemainder(a int, b int) (int, int) {
  let quotient = a / b
  let remainder = a % b
  quotient, remainder  // automatically returned
}

// Usage
let (q, r) = divideWithRemainder(17, 5)
```

### Early Return
```ms
fn processValue(x int) string {
  if x < 0 {
    return "negative"  // explicit return for early exit
  }
  
  if x == 0 {
    return "zero"      // explicit return for early exit
  }
  
  "positive"  // automatically returned
}
```

## Error Handling

Functions can return errors using the bang (`!`) syntax:

### Error-Returning Function
```ms
fn divide(a int, b int) int! {
  if b == 0 {
    error("division by zero")  // return keyword optional
  }
  a / b  // automatically returned
}
```

### Using Error-Returning Functions
```ms
fn main() {
  let result = try divide(10, 2)  // result = 5
  print("Result: " + string(result))
  
  // Handling potential errors
  let errorResult = try divide(10, 0)
  // Error is handled by try expression
}
```

### Multiple Returns with Errors
```ms
fn parseNumber(text string) (int, bool)! {
  if text == "" {
    error("empty string")  // return keyword optional
  }
  
  let num = parseInt(text)
  let isValid = num != null
  num, isValid  // automatically returned
}
```

## Function Expressions

You can create anonymous functions:

```ms
let add = fn(a int, b int) int {
  a + b  // automatically returned
}

let result = add(5, 3)  // result = 8
```

### Closures
Closures are like functions with photographic memory. They remember the environment where they were born, even if they travel far, far away in your code. Spooky, yet useful!
```ms
fn createCounter() (fn() int) {
  let count = 0
  fn() int {
    count = count + 1
    count  // automatically returned
  }
}

let counter = createCounter()
print(counter())  // 1
print(counter())  // 2
```

## Main Function

Every manuscript program starts with a `main` function:

```ms
fn main() {
  print("Hello, manuscript!")
}
```

### Main with Arguments
```ms
fn main(args string[]) {
  if args.length > 0 {
    print("First argument: " + args[0])
  }
}
```

## Advanced Features

### Higher-Order Functions
```ms
fn applyOperation(a int, b int, op (fn(int, int) int)) int {
  op(a, b)  // automatically returned
}

let add = fn(x int, y int) int { x + y }  // automatically returned
let multiply = fn(x int, y int) int { x * y }  // automatically returned

let sum = applyOperation(5, 3, add)      // 8
let product = applyOperation(5, 3, multiply)  // 15
```

### Function as Return Value
```ms
fn getOperation(op string) (fn(int, int) int) {
  if op == "add" {
    fn(a int, b int) int { a + b }  // automatically returned
  } else if op == "multiply" {
    fn(a int, b int) int { a * b }  // automatically returned
  }
  fn(a int, b int) int { 0 }  // automatically returned
}
```

## Type Annotations

### Function Types
```ms
// Function type: (fn(int, int) int)
let operation (fn(int, int) int)

// Assign a function
operation = fn(a int, b int) int {
  a + b  // automatically returned
}
```

### Optional Parameters
```ms
fn request(url string, method string = "GET", headers map[string]string = [:]) {
  // implementation
}
```

## Examples

### Data Processing
```ms
fn processNumbers(numbers int[]) int[] {
  let results = []
  for num in numbers {
    if num > 0 {
      results.append(num * 2)
    }
  }
  results  // automatically returned
}
```

### Validation Function
```ms
fn validateEmail(email string) bool! {
  if email == "" {
    error("email cannot be empty")  // return keyword optional
  }
  
  if !email.contains("@") {
    error("invalid email format")  // return keyword optional
  }
  
  true  // automatically returned
}
```

### Configuration Builder
```ms
fn createConfig(env string) Config! {
  if env == "production" {
    Config{
      debug: false,
      apiUrl: "https://api.production.com",
      timeout: 5000
    }  // automatically returned
  } else if env == "development" {
    Config{
      debug: true,
      apiUrl: "http://localhost:3000",
      timeout: 1000
    }  // automatically returned
  }
  
  error("unknown environment: " + env)  // return keyword optional
}
```

### Recursive Function
```ms
fn factorial(n int) int {
  if n <= 1 {
    return 1  // explicit return for early exit
  }
  n * factorial(n - 1)  // automatically returned
}
```

## Best Practices

### Naming
- Use descriptive names: `calculateTax` instead of `calc`
- Use verbs for actions: `processData`, `validateInput`
- Use `is` or `has` for boolean functions: `isValid`, `hasPermission`

### Error Handling
- Use bang functions (`!`) for operations that can fail
- Provide meaningful error messages
- Handle errors at appropriate levels

### Parameters
- Limit the number of parameters (prefer objects for many parameters)
- Use default values for optional parameters
- Group related parameters into structs when appropriate 