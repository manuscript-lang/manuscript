---
title: "Error Handling"
linkTitle: "Error Handling"

description: >
  Error handling with bang functions, try expressions, and check statements in manuscript.
---

Let's be honest, sometimes things go wrong. Your program might try to divide by zero (math teachers warned us!), or a file might play hide-and-seek. Manuscript's error handling is your toolkit for dealing with these little oopsies gracefully, without your whole program throwing a tantrum.

**Note:** Remember our chill `return` keyword from the Functions chapter? It's just as relaxed here. Even when errors are involved, the `return` is often optional – the last expression, be it a value or an `error(...)`, is what gets sent back.

## Bang Functions
Functions that might throw a metaphorical wrench in the works use the `!` (bang!) symbol. It's like a little warning sign: 'Handle with care, this one *could* get spicy!'

Function has a kick,
Beware the bang, it might pop!
Handle errors well.

Functions that can return errors use the `!` syntax:

### Declaring Error-Returning Functions
```ms
fn divide(a int, b int) int! {
  if b == 0 {
    error("division by zero")  // return keyword optional // Classic math no-no!
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
  // Error is propagated up the call stack // Uh oh, this one's gonna make some noise!
}
```

## Try Expressions

The `try` keyword is your brave error explorer. You `try` to run a bang function, and if an error pops up, `try` catches it and lets you decide what to do next – maybe propagate it, or handle it with a `catch`. It handles errors from bang functions:

### Basic Try
```ms
let result = try parseNumber("42")
// If parseNumber succeeds, result contains the value
// If it fails, error is propagated to caller // Fingers crossed!
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

Errors in Manuscript are like well-trained carrier pigeons. If one function doesn't know how to handle an error, it sends it up to the function that called it, and so on, until someone deals with it or it reaches the top (hopefully with a global error handler!). Errors automatically propagate up the call stack:

```ms
fn levelThree() int! {
  error("something went wrong")  // return keyword optional // It all started here...
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
`check` statements are your function's personal bodyguards. They verify conditions upfront. If a check fails, the function makes a swift exit, returning an error. No messing around!

Use `check` for validation that should exit the function:

```ms
fn validateInput(data Input) Result! {
  check data.name != ""           // exits if false // Must have a name!
  check data.age > 0              // exits if false // Age must be positive, no Benjamin Buttons here.
  check data.email.contains("@")  // exits if false
  
  // If all checks pass, continue processing
  processValidInput(data)  // automatically returned
}
```

## Error Types

### Creating Custom Errors
Sometimes, the built-in error messages are like a generic 'Something went wrong.' With custom errors, you can be the playwright of your program's drama, crafting specific and helpful error messages. 'Error: User not found, ID: 123. Perhaps they're on a coffee break?'
```ms
fn validateAge(age int) void! {
  if age < 0 {
    error("age cannot be negative")  // return keyword optional
  }
  if age > 150 {
    error("age seems unrealistic")  // return keyword optional // Unless they're a vampire?
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
Got a bang function but want to provide a default value if it misbehaves? `try operation() catch defaultValue` is your safety net. If `operation()` trips, `defaultValue` steps in. Smooth.
```ms
fn safeDivide(a int, b int) int {
  let result = try divide(a, b) catch 0 // If divide freaks out, we just get 0. Calm.
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
- Be specific! 'Error: It broke' isn't helpful. 'Error: File 'unicorn.txt' not found in '/magical/forest'' – now that's an error message with a story!
- Be specific about what went wrong (really, we can't stress this enough).
- Include relevant context (values, parameters) – what were you *trying* to do?
- Use consistent error message format – make your errors look like they belong to the same family.

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
- Don't just sweep errors under the rug! Face them, handle them, or consciously let them propagate. Your future self (and your users) will thank you.
- Handle errors at the appropriate level – don't make the intern (a low-level function) deal with a company-wide crisis (a critical error).
- Don't ignore errors (use explicit handling) – this is the programming equivalent of sticking your fingers in your ears and humming.
- Use try when you want errors to propagate – let someone else deal with it, but do it formally.
- Use defensive programming with validation – an ounce of prevention is worth a pound of cure (and less debugging headaches).

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
  defer file.close()  // Always close, even on error // Good hygiene!
  
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