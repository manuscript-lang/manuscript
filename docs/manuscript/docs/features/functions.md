---
title: "Functions: Crafting Your Code's Reusable Magic Spells"
linkTitle: "Functions"

description: >
  Unveiling the secrets of function definitions, parameters, return types, error handling, and other enchanting aspects of Manuscript functions.
---

Welcome, apprentice sorcerers and seasoned code wizards! In the mystical realm of Manuscript, **functions** are your primary magic spells. They are reusable blocks of code that perform specific tasks, saving you from chanting the same incantations over and over. We declare these wondrous constructs using the `fn` keyword. They can accept ingredients (parameters), conjure results (return types), have default potion recipes (default values), and even warn you if the spell might backfire (error handling).

**A Friendly Reminder:** The `return` keyword is often a bit shy in Manuscript. Functions are pretty chill and will automatically return the value of their last expression if you don't explicitly tell them to `return` something sooner.

## Basic Spellcraft: Function Declaration 101

Let's start with the fundamental ways to scribe your functions.

### Simple Function: Your First "Hello, World!" Incantation
The most basic spell, requiring no special ingredients.

```ms
// This function, when called, simply greets the universe.
fn greet() {
  print("Hello, World from a Manuscript function!")
}
```

### Function with Parameters: Adding Ingredients to Your Potion
Most spells need some input to work their magic. These are called parameters.

```ms
// This greet function is a bit more personal.
fn greet(name string) { // 'name' is a parameter of type 'string'
  print("Hello, " + name + "! Fancy meeting you here.")
}
```

### Function with Return Type: Conjuring Results
Sometimes, a spell produces something tangible. That's a return value.

```ms
// This function takes two integers and returns their sum.
fn add(a int, b int) int { // The 'int' after the parameters declares the return type.
  a + b // This sum is automatically returned. No 'return' keyword needed here!
}
```

## Parameters: The Necessary Ingredients

Parameters are the inputs your function needs to do its job.

### Required Parameters: "You Must Provide These!"
Some ingredients are absolutely essential.

```ms
// To calculate an area, width and height are non-negotiable.
fn calculateArea(width float, height float) float {
  width * height // The calculated area is returned.
}
```

### Default Parameters: "Use This If Nothing Else Is Specified"
For some ingredients, you can have a standard version ready to go.

```ms
// A versatile greeting function.
fn greet(name string, greeting string = "Salutations") { // "Salutations" is the default.
  print(greeting + ", " + name + "! Have a splendid day.")
}

// How to call it:
// greet("Alice")              // Uses default: "Salutations, Alice! Have a splendid day."
// greet("Bob", "Yo")          // Custom greeting: "Yo, Bob! Have a splendid day."
```

### Multiple Parameters: Juggling Many Ingredients
Functions can take multiple parameters of various types.

```ms
// A function to set up a new user profile (details omitted for brevity).
fn createUser(name string, age int, email string, active bool) {
  print("Creating user: " + name + ", Age: " + string(age) + ", Email: " + email + ", Active: " + string(active))
  // ... actual user creation logic would go here ...
}
```

## Return Values: The Fruits of Your Labor

What your function gives back after performing its task.

### Single Return Value: One Treasure to Rule Them All
Most often, a function returns a single piece of information.

```ms
// This function simply doubles an integer.
fn double(x int) int {
  x * 2 // The doubled value is returned.
}
```

### Multiple Return Values: A Bounty of Results!
Sometimes, a function has more than one gift to bestow. Manuscript handles this with grace.

```ms
// This function performs integer division and returns both the quotient and the remainder.
fn divideWithRemainder(a int, b int) (int, int) { // Returns two integers!
  let quotient = a / b
  let remainder = a % b
  quotient, remainder // Both are returned, neat!
}

// How to receive these multiple treasures:
// let (q, r) = divideWithRemainder(17, 5) // q gets 17/5 (3), r gets 17%5 (2)
// print("17 divided by 5 is " + string(q) + " with a remainder of " + string(r))
```

### Early Return: "My Job Here Is Done (Ahead of Schedule!)"
If you need to exit a function before reaching the end, use an explicit `return`.

```ms
// This function determines if a number is positive, negative, or zero.
fn checkNumber(x int) string {
  if x < 0 {
    return "negative" // Explicit return for an early exit.
  }
  
  if x == 0 {
    return "zero"     // Another early exit.
  }
  
  "positive" // If neither of the above, it must be positive. This is auto-returned.
}
```
> Code block takes form,
> Does one thing, and does it well,
> Logic's neat helper.

## Error Handling: When Spells Go Awry

Functions can signal that something went wrong using the bang (`!`) syntax. (See the Error Handling scrolls for more on this!)

### Error-Returning Function: "Beware, I Might Complain!"
This function bravely admits it might not succeed.

```ms
// Our old friend, the division function, now with error potential.
fn divide(a int, b int) int! { // The '!' means "I might return an error instead of an int."
  if b == 0 {
    error("Division by zero! A cosmic impossibility.") // This exits and signals an error.
  }
  a / b // Returned if all is well.
}
```

### Using Error-Returning Functions: Handling with `try`
When calling a function that might error, you typically use `try`.

```ms
fn main_error_example() {
  let result = try divide(10, 2) // If divide succeeds, result gets 5.
  print("Result of 10/2: " + string(result))
  
  print("Attempting the forbidden division by zero...")
  let errorResult = try divide(10, 0) // This will trigger the error.
  // If not caught, this error would propagate. In main, it might halt the program.
  // To handle it gracefully, you'd use 'try ... catch'.
  print("If you see this, the error from divide(10,0) was handled or propagated past main.")
}
```

### Multiple Returns with Errors: A Mixed Bag of Success and Danger
A function can be designed to return multiple values OR an error.

```ms
// Tries to parse text into a number and also tells you if it thinks it's valid.
fn parseNumber(text string) (int, bool)! { // Returns (int, bool) on success, or an error.
  if text == "" {
    error("Empty string provided. Cannot parse nothingness.")
  }
  
  // Simplified parsing logic for example:
  let num = 0
  let isValid = false
  if text == "42" {
    num = 42
    isValid = true
  } else if text == "100" {
    num = 100
    isValid = true
  } else {
    // In a real scenario, you might return an error here if parsing truly fails.
    // For this example, we'll say it "succeeds" but returns isValid = false.
    // Or, to make it a true error case for non-parseable:
    // error("Cannot parse '" + text + "' into a number.")
  }

  num, isValid // Returned on success.
}
```

## Function Expressions: Anonymous Magic and Hidden Powers

You can create functions without giving them a formal name. These are known as anonymous functions or function literals.

```ms
// Assigning an anonymous function to a variable 'add'.
let add = fn(a int, b int) int { // No function name after 'fn' here!
  a + b
}

let result = add(5, 3) // result becomes 8. The anonymous function is called via 'add'.
// print("5 + 3 via anonymous function = " + string(result))
```

### Closures: Functions with a Photographic Memory
A closure is a function that "remembers" the environment in which it was created, even if that environment is gone. Spooky, yet powerful!

```ms
// This function creates and returns another function (a counter).
fn createCounter() (fn() int) { // It returns a function that takes no args and returns an int.
  let count = 0 // 'count' is a local variable within createCounter.

  // This inner anonymous function is the closure.
  // It "closes over" and remembers 'count' from its parent scope.
  fn() int {
    count = count + 1 // It can access and modify 'count'.
    count // Returns the updated count.
  }
}

let counterA = createCounter()
// print(counterA())  // Outputs: 1 (count in counterA's closure is now 1)
// print(counterA())  // Outputs: 2 (count in counterA's closure is now 2)

let counterB = createCounter() // A completely separate counter with its own 'count'.
// print(counterB())  // Outputs: 1
```

## The `main` Function: Where Your Program's Story Begins

Every Manuscript saga (program) needs a starting point. This is the `main` function.

```ms
fn main() { // The grand entrance!
  print("Hello from the main function! Let the adventure begin.")
}
```

### Main with Arguments: Receiving Instructions from the Outside World
Your program can receive command-line arguments if your `main` function is set up to accept them.

```ms
// This main function can accept an array of strings (command-line arguments).
fn main(args string[]) {
  if args.length() > 0 {
    print("I received some instructions! The first one is: " + args[0])
  } else {
    print("No instructions given from the command line.")
  }
}
```

## Advanced Spellcasting: More Function Features

For the truly ambitious sorcerer.

### Higher-Order Functions: Functions as Esteemed Colleagues
These are functions that either take other functions as parameters, return functions, or both. Very meta!

```ms
// 'applyOperation' takes two numbers and a function 'op'.
// 'op' itself must be a function that takes two ints and returns an int.
fn applyOperation(a int, b int, op (fn(int, int) int)) int {
  op(a, b) // Calls the provided 'op' function.
}

let addOperation = fn(x int, y int) int { x + y }
let multiplyOperation = fn(x int, y int) int { x * y }

let sumResult = applyOperation(10, 5, addOperation)      // sumResult is 15
let productResult = applyOperation(10, 5, multiplyOperation)  // productResult is 50
// print("Sum via HOF: " + string(sumResult))
// print("Product via HOF: " + string(productResult))
```

### Function as Return Value: Conjuring Other Functions
A function can manufacture and return a brand new function. We saw this with `createCounter`!

```ms
// This function returns a specific arithmetic function based on the 'op' string.
fn getOperation(opSymbol string) (fn(int, int) int) { // Returns a function!
  if opSymbol == "+" {
    fn(a int, b int) int { a + b } // Return the 'add' function
  } else if opSymbol == "*" {
    fn(a int, b int) int { a * b } // Return the 'multiply' function
  }
  // Default: return a function that does nothing exciting.
  fn(a int, b int) int {
    print("Unknown operation: " + opSymbol + ". Returning 0.")
    0
  }
}

let chosenOperation = getOperation("+")
// print("Result of chosenOperation(7,3): " + string(chosenOperation(7,3))) // Should be 10
```

## Type Annotations: Being Explicit About Your Magic

Sometimes, you need to be very clear about the types of functions you're working with.

### Function Types: Describing a Function's Signature
You can define a variable that is meant to hold a function of a specific signature.

```ms
// 'operation' is declared as a variable that can hold a function.
// This function must take two integers and return an integer.
let operation (fn(int, int) int)

// Now, assign a compatible anonymous function to it.
operation = fn(a int, b int) int {
  a + b
}
// print("Result of 'operation(10, 20)': " + string(operation(10,20)))
```

### Optional Parameters with Defaults (Revisited)
Just a reminder that default parameter values are part of a function's charm.

```ms
// Makes an HTTP request (details omitted). 'method' and 'headers' are optional.
fn request(url string, method string = "GET", headers map[string]string = [:]) {
  print("Requesting URL: " + url + " with method: " + method)
  // ... actual request logic ...
}
// request("http://example.com") // Uses defaults for method and headers
// request("http://example.com/api", "POST") // Custom method, default headers
```

## Examples from the Grimoire

A few practical spells to illustrate these concepts.

### Data Processing: Sifting Through a List
A function that processes a list of numbers.

```ms
fn processNumbers(numbers int[]) int[] {
  let results = [] // Start with an empty list for our results
  for num in numbers {
    if num > 0 { // Only interested in positive numbers
      results.append(num * 2) // Double them and add to results
    }
  }
  results // Return the list of processed numbers
}
```

### Validation Function: Checking for Proper Incantations
A function to validate an email address.

```ms
fn validateEmail(email string) bool! { // Might error if you're feeling strict
  if email == "" {
    error("Email cannot be an empty void.")
  }
  
  if !email.contains("@") { // A very basic check for an "@" sign.
    error("Invalid email format: missing the sacred '@' symbol.")
  }
  
  true // If we reach here, it's (basically) valid!
}
```

### Configuration Builder: Crafting Settings Based on Environment
A function to create configuration objects.

```ms
// Assume 'Config' is a custom type defined elsewhere.
// Config{ debug bool, apiUrl string, timeout int }

fn createConfig(env string) Config! { // Might error if env is unknown
  if env == "production" {
    Config{
      debug: false,
      apiUrl: "https://api.production.com/realmagic",
      timeout: 5000 // milliseconds
    }
  } else if env == "development" {
    Config{
      debug: true,
      apiUrl: "http://localhost:3000/testspells",
      timeout: 1000
    }
  }
  
  error("Unknown environment: '" + env + "'. Choose wisely: 'production' or 'development'.")
}
```

### Recursive Function: Spells That Call Themselves
A function that calls itself to solve a problem. The classic factorial example!

```ms
fn factorial(n int) int {
  if n <= 1 { // Base case: the spell stops here for 1 or 0.
    return 1 // Explicit return is often used for base cases in recursion.
  }
  // Recursive step: n times factorial of (n-1).
  n * factorial(n - 1)
}
// print("Factorial of 5 is: " + string(factorial(5))) // 5*4*3*2*1 = 120
```

## Function Whisperer's Guide: Best Practices

Some friendly advice for writing functions that are effective, readable, and don't cause too many headaches.

### Naming Your Spells Wisely
- Use descriptive names that clearly indicate what the function does (e.g., `calculateSalesTax` is better than just `calc` or `taxFunc`).
- Start with a verb for functions that perform an action (e.g., `processUserData`, `validateInputFile`).
- For functions that return a boolean, often prefixing with `is` or `has` makes sense (e.g., `isValidUser`, `hasAdminPrivileges`).

### Handling Potential Mishaps (Error Handling)
- Use the bang (`!`) syntax for functions that might fail (e.g., network requests, file operations). This signals to the caller that they need to handle potential errors.
- Provide clear and informative error messages. Your future self (and others) will thank you.
- Handle errors at the appropriate level. Sometimes it's best to let an error propagate; other times, you should catch it and recover.

### Managing Your Ingredients (Parameters)
- Try to limit the number of parameters a function takes. If you have many (say, more than 3 or 4), consider grouping them into an object or a custom type. This makes the function call cleaner.
- Use default values for parameters that are genuinely optional, making the function easier to call in common cases.
- Group related parameters into structs (custom types) if they logically belong together and are passed around frequently.
