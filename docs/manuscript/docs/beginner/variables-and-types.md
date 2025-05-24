---
title: "Variables and Types"
linkTitle: "Variables and Types"
weight: 1
description: >
  Learn how to declare variables, work with different data types, and understand type inference in Manuscript.
---

Variables are containers that store data values. Manuscript uses the `let` keyword to declare variables and supports both type inference and explicit type annotations.

## Variable Declaration

### Basic Declaration

Use `let` to declare variables:

```ms
fn main() {
  let name = "Alice"
  let age = 25
  let height = 5.6
  let active = true
  
  print("Name: " + name)
  print("Age: " + string(age))
}
```

### Type Inference

Manuscript automatically infers types from values:

```ms
fn main() {
  let message = "Hello"        // inferred as string
  let count = 42              // inferred as int
  let price = 19.99           // inferred as float
  let ready = true            // inferred as bool
  let data = null             // inferred as null type
}
```

### Explicit Types

You can specify types explicitly when needed:

```ms
fn main() {
  let name string = "Alice"
  let age int = 25
  let height float = 5.6
  let active bool = true
}
```

## Data Types

### Numbers

#### Integers

```ms
fn main() {
  // Basic integers
  let positive = 123
  let negative = -456
  let zero = 0
  let large = 9876543210
  
  // From expressions
  let sum = 10 + 20
  let difference = 100 - 50
  
  print("Sum: " + string(sum))
}
```

#### Different Number Bases

```ms
fn main() {
  let binary = 0b1010      // Binary (10 in decimal)
  let hex = 0xFF           // Hexadecimal (255 in decimal)
  let octal = 0o777        // Octal (511 in decimal)
  
  print("Binary: " + string(binary))
  print("Hex: " + string(hex))
  print("Octal: " + string(octal))
}
```

#### Floating Point Numbers

```ms
fn main() {
  let positive = 1.23
  let negative = -0.005
  let zero = 0.0
  let noLeading = .5       // Same as 0.5
  
  // From expressions
  let sum = 0.5 + 1.2
  let quotient = 10.0 / 4.0
  
  print("Quotient: " + string(quotient))
}
```

### Strings

#### Basic Strings

```ms
fn main() {
  let singleQuoted = 'Hello, World!'
  let doubleQuoted = "Hello, World!"
  
  print(singleQuoted)
  print(doubleQuoted)
}
```

#### Multi-line Strings

```ms
fn main() {
  let multiLine = '''
This is a multi-line string.
It can contain multiple lines of text.
Perfect for documentation or long text.
'''
  
  let multiDouble = """
Another multi-line string
using double quotes.
"""
  
  print(multiLine)
}
```

#### String Interpolation

```ms
fn main() {
  let name = "Alice"
  let age = 25
  
  let greeting = "Hello, ${name}! You are ${age} years old."
  print(greeting)
  
  // Works with expressions
  let message = "In 5 years, you'll be ${age + 5}"
  print(message)
}
```

### Booleans

```ms
fn main() {
  let isTrue = true
  let isFalse = false
  
  // From comparisons
  let isAdult = age >= 18
  let isEqual = 10 == 10
  let isGreater = 10 > 5
  
  print("Is adult: " + string(isAdult))
}
```

### Null and Void

```ms
fn main() {
  let empty = null         // Represents absence of value
  let nothing = void       // Represents no return value
  
  print("Empty: " + string(empty))
}
```

## Advanced Variable Declarations

### Block Declarations

Declare multiple variables in a block:

```ms
fn main() {
  let (
    username = "alice"
    password = "secret"
    active = true
    attempts = 0
  )
  
  print("User: " + username)
  print("Active: " + string(active))
}
```

### Destructuring Objects

Extract values from objects:

```ms
fn main() {
  let person = {
    name: "Alice"
    age: 30
    city: "New York"
  }
  
  let {name, age} = person
  
  print("Name: " + name)
  print("Age: " + string(age))
}
```

### Destructuring Arrays

Extract values from arrays:

```ms
fn main() {
  let coordinates = [10, 20]
  let colors = ["red", "green", "blue"]
  
  let [x, y] = coordinates
  let [first, second, third] = colors
  
  print("X: " + string(x) + ", Y: " + string(y))
  print("First color: " + first)
}
```

### Complex Destructuring

Mix different destructuring patterns:

```ms
fn main() {
  let (
    name = "Alice"
    age = 30
    {city, country} = {city: "NYC", country: "USA"}
    [r, g, b] = [255, 128, 64]
  )
  
  print("${name} lives in ${city}, ${country}")
  print("Color: rgb(${r}, ${g}, ${b})")
}
```

## Variable Assignment

### Basic Assignment

```ms
fn main() {
  let count = 0
  count = 10
  count = count + 5
  
  print("Count: " + string(count))
}
```

### Compound Assignment

```ms
fn main() {
  let x = 10
  
  x += 5     // x = x + 5
  x -= 3     // x = x - 3
  x *= 2     // x = x * 2
  x /= 4     // x = x / 4
  x %= 3     // x = x % 3
  
  print("Final x: " + string(x))
}
```

## Type Conversion

### Explicit Conversion

```ms
fn main() {
  let age = 25
  let price = 19.99
  let active = true
  
  // Convert to string
  let ageStr = string(age)
  let priceStr = string(price)
  let activeStr = string(active)
  
  // Convert between numbers
  let ageFloat = float(age)
  let priceInt = int(price)    // Truncates decimal
  
  print("Age as string: " + ageStr)
  print("Price as int: " + string(priceInt))
}
```

### Parsing from Strings

```ms
fn main() {
  let numberStr = "42"
  let floatStr = "3.14"
  let boolStr = "true"
  
  let number = parseInt(numberStr)
  let decimal = parseFloat(floatStr)
  let flag = parseBool(boolStr)
  
  print("Parsed number: " + string(number))
  print("Parsed float: " + string(decimal))
  print("Parsed bool: " + string(flag))
}
```

## Variable Scope

### Function Scope

Variables declared in functions are local to that function:

```ms
fn demonstrate() {
  let localVar = "I'm local to this function"
  print(localVar)
}

fn main() {
  let mainVar = "I'm in main"
  demonstrate()
  
  // localVar is not accessible here
  print(mainVar)
}
```

### Block Scope

Variables declared in blocks are local to that block:

```ms
fn main() {
  let outer = "outer scope"
  
  {
    let inner = "inner scope"
    print(outer)  // Can access outer
    print(inner)  // Can access inner
  }
  
  print(outer)    // Can still access outer
  // print(inner) // ERROR: inner not accessible here
}
```

## Best Practices

### Use Descriptive Names

```ms
fn main() {
  // Good
  let userAge = 25
  let isAccountActive = true
  let totalPrice = 99.99
  
  // Avoid
  let a = 25
  let flag = true
  let x = 99.99
}
```

### Use Type Annotations for Clarity

```ms
fn main() {
  // When the type isn't obvious, be explicit
  let users []User = []
  let config Config = loadDefaultConfig()
  let timeout int = 30 // seconds
}
```

### Group Related Variables

```ms
fn main() {
  // Use block declarations for related variables
  let (
    dbHost = "localhost"
    dbPort = 5432
    dbName = "myapp"
    dbUser = "admin"
  )
}
```

### Initialize Variables When Possible

```ms
fn main() {
  // Good - clear intent
  let count = 0
  let total = 0.0
  let items = []
  
  // Avoid - unclear state
  let count int
  let total float
  let items []string
}
```

## Common Patterns

### Swapping Variables

```ms
fn main() {
  let a = 10
  let b = 20
  
  // Traditional swap
  let temp = a
  a = b
  b = temp
  
  print("a: " + string(a) + ", b: " + string(b))
}
```

### Default Values

```ms
fn main() {
  let userInput = getUserInput()
  let name = userInput != null ? userInput : "Anonymous"
  
  print("Hello, " + name)
}
```

### Conditional Assignment

```ms
fn main() {
  let score = 85
  let grade = score >= 90 ? "A" : score >= 80 ? "B" : "C"
  
  print("Grade: " + grade)
}
```

## Exercises

Try these exercises to practice what you've learned:

### Exercise 1: Personal Information

```ms
fn main() {
  // Declare variables for personal information
  let name = "Your Name"
  let age = 25
  let height = 5.8
  let isStudent = false
  
  // Print a formatted message
  print("Name: ${name}")
  print("Age: ${age}")
  print("Height: ${height} feet")
  print("Student: ${isStudent}")
}
```

### Exercise 2: Calculator

```ms
fn main() {
  let a = 15
  let b = 4
  
  let sum = a + b
  let difference = a - b
  let product = a * b
  let quotient = float(a) / float(b)
  let remainder = a % b
  
  print("${a} + ${b} = ${sum}")
  print("${a} - ${b} = ${difference}")
  print("${a} * ${b} = ${product}")
  print("${a} / ${b} = ${quotient}")
  print("${a} % ${b} = ${remainder}")
}
```

### Exercise 3: Destructuring Practice

```ms
fn main() {
  let coordinates = [100, 200, 300]
  let [x, y, z] = coordinates
  
  let person = {
    firstName: "John"
    lastName: "Doe"
    email: "john@example.com"
  }
  let {firstName, lastName} = person
  
  print("Point: (${x}, ${y}, ${z})")
  print("Person: ${firstName} ${lastName}")
}
```

## Next Steps

Now that you understand variables and types:

1. **[Learn about Functions](../functions/)** - Organize your code with functions
2. **[Master Control Flow](../control-flow/)** - Make decisions and repeat actions
3. **[Work with Collections](../data-structures/)** - Handle multiple values

{{% alert title="Practice Makes Perfect" %}}
The best way to learn variables and types is to use them! Try creating programs that store and manipulate different kinds of data.
{{% /alert %}} 