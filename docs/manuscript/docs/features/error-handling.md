---
title: "Error Handling"
linkTitle: "Error Handling"
weight: 50
description: >
  Error handling with bang functions, try expressions, and check statements in manuscript.
---

manuscript provides built-in error handling mechanisms including bang functions, try expressions, and check statements for robust error management.

**Note:** The `return` keyword is optional in manuscript. Functions automatically return the value of the last expression.

## Bang Functions

Functions that can return errors use the `!` syntax:

### Declaring Error-Returning Functions
```ms
fn divide(a int, b int) int! {
  if b == 0 {
    error("division by zero")  // return keyword optional
  }
  a / b  // automatically returned
}

fn parseNumber(text string) int! {
  if text == "" {
    error("empty string")  // return keyword optional
  }
  // parsing logic...
  result  // automatically returned
}
```

### Using Bang Functions
```ms
fn main() {
  let result = try divide(10, 2)
  print("Result: " + string(result))  // Result: 5
  
  let errorCase = try divide(10, 0)
  // Error is propagated up the call stack
}
```

## Try Expressions

The `try` keyword handles errors from bang functions:

### Basic Try
```ms
let result = try parseNumber("42")
// If parseNumber succeeds, result contains the value
// If it fails, error is propagated to caller
```

### Try in Function Calls
```ms
fn processFile(filename string) string! {
  let content = try readFile(filename)
  let parsed = try parseData(content)
  processData(parsed)  // automatically returned
}
```

### Chaining Try Operations
```ms
fn complexOperation() int! {
  let a = try operation1()
  let b = try operation2(a)
  let c = try operation3(b)
  c  // automatically returned
}
```

## Error Propagation

Errors automatically propagate up the call stack:

```ms
fn levelThree() int! {
  error("something went wrong")  // return keyword optional
}

fn levelTwo() int! {
  try levelThree()  // error propagates, automatically returned
}

fn levelOne() int! {
  try levelTwo()    // error propagates, automatically returned
}

fn main() {
  let result = try levelOne()
  // Error from levelThree reaches here
}
```

## Check Statements

Use `check` for validation that should exit the function:

```ms
fn validateInput(data Input) Result! {
  check data.name != ""           // exits if false
  check data.age > 0              // exits if false
  check data.email.contains("@")  // exits if false
  
  // If all checks pass, continue processing
  processValidInput(data)  // automatically returned
}
```

## Error Types

### Creating Custom Errors
```ms
fn validateAge(age int) void! {
  if age < 0 {
    error("age cannot be negative")  // return keyword optional
  }
  if age > 150 {
    error("age seems unrealistic")  // return keyword optional
  }
}
```

### Error Messages
```ms
fn connectToDatabase(url string) Connection! {
  if url == "" {
    error("database URL is required")  // return keyword optional
  }
  
  if !isValidUrl(url) {
    error("invalid database URL format: " + url)  // return keyword optional
  }
  
  // connection logic...
}
```

## Handling Errors at Different Levels

### Function Level
```ms
fn safeDivide(a int, b int) int {
  let result = try divide(a, b) catch 0
  result  // automatically returned
}
```

### Application Level
```ms
fn main() {
  let files = ["data1.txt", "data2.txt", "data3.txt"]
  
  for file in files {
    let content = try processFile(file)
    print("Processed " + file + ": " + content)
  }
}
```

## Best Practices

### Error Messages
- Be specific about what went wrong
- Include relevant context (values, parameters)
- Use consistent error message format

```ms
fn withdraw(account Account, amount float) void! {
  if amount <= 0 {
    error("withdrawal amount must be positive, got: " + string(amount))  // return keyword optional
  }
  
  if account.balance < amount {
    error("insufficient funds: balance=" + string(account.balance) + 
                ", requested=" + string(amount))  // return keyword optional
  }
}
```

### Error Handling Strategy
- Handle errors at the appropriate level
- Don't ignore errors (use explicit handling)
- Use try when you want errors to propagate
- Use defensive programming with validation

### Function Design
```ms
// Good: Clear error conditions
fn createUser(email string, age int) User! {
  check email != ""
  check email.contains("@")
  check age >= 0 && age <= 150
  
  User{email: email, age: age}  // automatically returned
}

// Good: Multiple error cases
fn parseConfig(filename string) Config! {
  let content = try readFile(filename)
  let json = try parseJSON(content)
  let config = try validateConfig(json)
  config  // automatically returned
}
```

## Common Patterns

### Resource Management
```ms
fn processFileData(filename string) Result! {
  let file = try openFile(filename)
  defer file.close()  // Always close, even on error
  
  let data = try file.readAll()
  processData(data)  // automatically returned
}
```

### Validation Chain
```ms
fn validateUser(data UserData) User! {
  let email = try validateEmail(data.email)
  let age = try validateAge(data.age)
  let name = try validateName(data.name)
  
  User{
    email: email,
    age: age,
    name: name
  }  // automatically returned
}
```

### Graceful Degradation
```ms
fn loadUserPreferences(userId string) Preferences {
  let prefs = try loadFromDatabase(userId) catch getDefaultPreferences()
  prefs  // automatically returned
}
```

### Bulk Operations
```ms
fn processMultipleFiles(filenames string[]) (Result[], Error[]) {
  let results = []
  let errors = []
  
  for filename in filenames {
    let result = try processFile(filename)
    if result.isError() {
      errors.append(result.error())
    } else {
      results.append(result.value())
    }
  }
  
  results, errors  // automatically returned
}
``` 