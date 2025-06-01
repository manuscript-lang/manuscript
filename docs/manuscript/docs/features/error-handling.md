---
title: "Error Handling: Gracefully Dodging Digital Banana Peels"
linkTitle: "Error Handling"

description: >
  Navigating Manuscript's error handling landscape with bang functions (!), try expressions, and check statements. Because sometimes, things go sideways!
---

Ah, errors. The uninvited guests at our coding party. But fear not! Manuscript provides some rather nifty tools to manage these digital oopsies, including functions that shout "I might fail!" (bang functions), expressions that bravely attempt risky operations (`try`), and statements that guard your functions like vigilant bouncers (`check`).

**A Little Note on Returns:** Remember, the `return` keyword is often optional in Manuscript. Functions are cool like that and will automatically return the value of their last expression.

## Bang Functions: The Drama Queens of an Error-Prone World!

Functions that know they might stir up trouble use the `!` syntax in their signature. This is their way of saying, "Hey, I could return an error, so handle me with care!"

### Declaring Error-Returning Functions: "I Might Explode!"
Here's how you define a function that's not afraid to admit its potential for... unexpected outcomes.

```ms
// This function attempts division, a notoriously risky business with zero.
fn divide(a int, b int) int! { // That '!' means "Watch out, I might error!"
  if b == 0 {
    error("division by zero - a mathematical faux pas!") // No 'return' needed, 'error' exits.
  }
  a / b // If all is well, this result is automatically returned.
}

// Tries to make sense of text as a number.
fn parseNumber(text string) int! {
  if text == "" {
    error("empty string - can't make a number from nothingness.")
  }
  // Imagine complex parsing logic here...
  let result = 42 // Let's pretend 'text' magically became 42
  result // This is returned if no error occurred.
}
```

### Using Bang Functions: "Okay, I'm Ready for Anything (I Think)"
When you call a bang function, you're acknowledging its risky nature.

```ms
fn main() {
  // We 'try' to call the risky function.
  let result = try divide(10, 2)
  print("Result of 10/2: " + string(result))  // Should be 5, if our math is right.
  
  print("Now for something a bit more daring...")
  let errorCase = try divide(10, 0)
  // If we reach here without the program stopping, it means the error
  // was handled further up, or we're in a context that expects propagation.
  // In a typical main(), an unhandled error would halt execution.
  print("If you see this, the error from divide(10,0) was handled or propagated past main.")
}
```

## Try Expressions: "Let's Attempt This, Shall We?"

The `try` keyword is your primary tool for calling bang functions. It's like saying, "I'm going to try this, and I'm aware it might not go as planned."

### Basic Try: The Optimist's Approach
Call the function, hope for the best. If it errors, the error doesn't just vanish; it typically propagates (travels up) to whoever called your current function.

```ms
// Assuming parseNumber(string) int! exists
let result = try parseNumber("42")
// If parseNumber("42") is successful, 'result' gets the value (e.g., 42).
// If parseNumber throws an error, that error continues its journey upwards.
```

### Try in Function Calls: Weaving a Web of Attempts
You can use `try` when calling functions that themselves call other bang functions. It's `try` all the way down!

```ms
// Imagine these functions exist and might return errors:
// readFile(string) string!
// parseData(string) DataObject!
// processData(DataObject) FinalResult!

fn processFile(filename string) FinalResult! { // This function also uses '!'
  let content = try readFile(filename)    // If this fails, processFile stops and passes the error up.
  let parsed = try parseData(content)     // If this fails, same deal.
  let processedResult = try processData(parsed) // And again.
  processedResult // If all tries succeed, this is returned.
}
```

### Chaining Try Operations: A Cascade of Courage
Sometimes, one risky operation depends on another.

```ms
// operation1()!
// operation2(outputOf1)!
// operation3(outputOf2)!

fn complexOperation() int! { // Notice the '!' - this whole chain can error.
  let a = try operation1()
  let b = try operation2(a)
  let c = try operation3(b)
  c // The grand result, if no gremlins appeared.
}
```

## Error Propagation: The Hot Potato Game

When a bang function called with `try` emits an error, and there's no immediate `catch` (which we'll see later), the error doesn't just disappear. It "propagates" up the call stack. Think of it as a hot potato being passed from function to function until someone handles it or it reaches the top and stops the program.

```ms
fn levelThree() int! {
  error("Houston, levelThree has a problem.") // Creates and "throws" an error.
}

fn levelTwo() int! {
  try levelThree() // Error from levelThree bubbles up through here.
                   // levelTwo implicitly re-throws it.
}

fn levelOne() int! {
  try levelTwo()   // Error from levelTwo (originally from levelThree) bubbles up.
                   // levelOne also implicitly re-throws it.
}

fn main() {
  print("Calling levelOne, wish us luck...")
  let result = try levelOne() // The error from levelThree makes its way here.
  // If this 'try' isn't followed by a 'catch', and main can't handle it,
  // the program will typically terminate and display the error.
  print("If you're reading this, levelOne somehow didn't error out. Surprising!")
}
```
> Oops, a wild bug,
> Code stumbles, then recovers,
> Grace under pressure.

## Check Statements: "You Shall Not Pass (With Invalid Data)!"

Use `check` for validations. If a `check` condition is false, the current function immediately stops and signals an error (similar to calling `error()`). It's for conditions that *must* be true to proceed.

```ms
// Assuming 'Input' is a type with fields: name, age, email
// And 'Result' is some type this function returns on success.
// And 'processValidInput(Input) Result!' is another function.

fn validateInput(data Input) Result! { // This function can error due to checks
  check data.name != ""           // If name is empty, function exits with an error.
  check data.age > 0              // If age is not positive, error exit.
  check data.email.contains("@")  // If email doesn't have '@', error exit.
  
  // If all checks pass, we're golden! Continue processing.
  print("All checks passed for: " + data.name)
  try processValidInput(data) // processValidInput itself might error, so we 'try' it.
}
```

## Error Types: Giving Your Errors Some Personality

You can create errors with specific messages to make debugging less of a detective game.

### Creating Custom Errors with Messages
When you use the `error()` function, you provide a string that becomes the error's message.

```ms
fn validateAge(age int) void! { // Returns nothing on success, or an error.
  if age < 0 {
    error("Age cannot be negative. Are you a time traveler?")
  }
  if age > 150 {
    error("Age " + string(age) + " seems a bit... optimistic. Re-check?")
  }
  // If no error, the function implicitly returns void.
}
```

### Informative Error Messages Are Your Friends
Good error messages can save you hours of head-scratching.

```ms
// Assuming Connection is a type and isValidUrl(string) bool exists.
fn connectToDatabase(url string) Connection! {
  if url == "" {
    error("Database URL is required. I can't guess where your data lives!")
  }
  
  if !isValidUrl(url) { // Let's pretend isValidUrl is a real function
    error("Invalid database URL format. Received: '" + url + "'. Expected something like 'protocol://host:port/database'.")
  }
  
  print("URL seems valid. Attempting to connect to " + url)
  // ... actual connection logic that might also error ...
  // return Connection{} // Placeholder for a successful connection object
}
```

## Handling Errors at Different Levels: Who Catches the Hot Potato?

You don't always have to let errors bubble all the way up. You can handle them at different points.

### Function Level: The `catch` Clause
You can use `try ... catch` to handle a potential error immediately and provide a fallback value or alternative logic.

```ms
// Remember our 'divide(a int, b int) int!' function?
fn safeDivide(a int, b int) int { // This function does NOT use '!' - it guarantees an int.
  let result = try divide(a, b) catch 0 // If divide(a,b) errors, use 0 instead.
  result // 'result' will be the division outcome or 0.
}

fn main_safeDivide() {
  print("Safe divide 10 by 2: " + string(safeDivide(10, 2)))   // Outputs 5
  print("Safe divide 10 by 0: " + string(safeDivide(10, 0)))   // Outputs 0
}
```

### Application Level: Deciding the Ultimate Fate
In your main application logic, you might loop through tasks and decide how to react to failures.

```ms
// processFile(filename string) string! is from earlier.
fn main_process_files() {
  let files = ["data1.txt", "data2.txt", "oops_no_such_file.txt", "data3.txt"]
  
  for file in files {
    // Using try...catch to handle errors per file
    let content = try processFile(file) catch {
      print("Failed to process '${file}': ${error}") // 'error' is a special var holding the error info
      continue // Skip to the next file
    }
    print("Successfully processed " + file + "! Content starts with: " + content.substring(0, 20))
  }
  print("File processing loop finished.")
}
```

## Words of Wisdom: Best Practices for Weathering Code Storms

A little foresight goes a long way in error handling.

### Crafting Excellent Error Messages
- **Be Specific:** "An error occurred" is not helpful. "Failed to read file: /path/to/nonexistent.txt - No such file or directory" is much better.
- **Include Context:** If an operation failed on a specific value, include that value (e.g., "Invalid user ID: -123").
- **Maintain Consistency:** Use a similar format for your error messages. It helps when scanning logs.

```ms
// Assuming Account is a type with a 'balance' field.
fn withdraw(account Account, amount float) void! {
  if amount <= 0 {
    error("Withdrawal amount must be positive, but got: " + string(amount))
  }
  
  if account.balance < amount {
    error("Insufficient funds. Current balance: " + string(account.balance) +
                ", requested withdrawal: " + string(amount) + ". Time to find a money tree?")
  }
  // ... actual withdrawal logic ...
  print("Withdrawal successful. Don't spend it all in one place!")
}
```

### Your Grand Error Handling Strategy
- **Handle at the Right Level:** Sometimes a low-level function should just pass an error up. Other times, it should handle it (e.g., with `catch`). Decide what makes sense for each situation.
- **Don't Just Ignore Errors:** Manuscript's system with `!` and `try` encourages you to acknowledge potential errors. Don't just `try someFunc() catch {}` everywhere without good reason!
- **`try` is for Propagation (Usually):** Use `try` when you intend for the error to be handled by an upstream caller, or if the current function is also a bang function.
- **Defensive Programming:** Use `check` statements and other validations to catch problems early, before they cause deeper errors.

### Designing Functions That Play Nice with Errors
```ms
// Good: Clear error conditions using 'check' for preconditions.
// Assuming User is a type.
fn createUser(email string, age int) User! {
  check email != "" && email.contains("@") // Invalid email? Function exits with an error.
  check age >= 0 && age <= 150            // Unrealistic age? Error exit.
  
  print("User data seems valid. Creating user: " + email)
  User{email: email, age: age} // If all checks pass, return the new User.
}

// Good: A function that clearly chains operations that might fail.
// Assuming Config is a type, and these bang functions exist:
// readFile(string) string!
// parseJSON(string) JSONValue!
// validateConfig(JSONValue) Config!
fn loadAndValidateConfig(filename string) Config! {
  let content = try readFile(filename)
  let json = try parseJSON(content)
  let config = try validateConfig(json)
  config // The final, validated config, or an error from any step.
}
```

## Common Patterns: Tried-and-True Error Tactics

Some scenarios pop up regularly. Here's how to handle them.

### Resource Management: The "Clean Up Your Mess" Pattern
`defer` is your best friend for ensuring resources (like files) are closed, even if errors occur.

```ms
// processData(string) Result!
// openFile(string) File! (where File has a close() method)
fn processFileData(filename string) Result! {
  let file = try openFile(filename) // This might error
  defer file.close()  // This will ALWAYS run when processFileData exits,
                      // whether normally or due to an error later on.
  
  let data = try file.readAll() // This might also error
  try processData(data) // And this too!
}
```

### Validation Chain: "One Check After Another"
Sequentially validate pieces of data. If one validation fails, the chain stops.

```ms
// validateEmail(string) string!, validateAge(int) int!, validateName(string) string!
// User is a type.
fn validateAndCreateUser(data UserData) User! { // UserData is some input struct
  let email = try validateEmail(data.email)
  let age = try validateAge(data.age)
  let name = try validateName(data.name)
  
  // If we got here, all validations passed!
  User{
    email: email,
    age: age,
    name: name
  }
}
```

### Graceful Degradation: "Making the Best of a Bad Situation"
If a preferred operation fails, fall back to a default or simpler behavior.

```ms
// loadFromDatabase(string) Preferences!
// getDefaultPreferences() Preferences
fn loadUserPreferences(userId string) Preferences { // Not a bang function! It always returns Preferences.
  // Try loading from DB. If it errors, catch it and return default preferences instead.
  let prefs = try loadFromDatabase(userId) catch getDefaultPreferences()
  prefs
}
```

### Bulk Operations: "Handling Many, Expecting Some Failures"
When processing many items, collect successes and failures separately.

```ms
// processFile(string) FileProcessingResult! (where FileProcessingResult has isError(), error(), value())
fn processMultipleFiles(filenames string[]) (Result[], ErrorInfo[]) { // Returns two arrays
  let successfulResults = []
  let encounteredErrors = []
  
  for filename in filenames {
    let result = try processFile(filename) // Attempt to process

    // This is a hypothetical way to check if 'result' is an error or success.
    // Manuscript's actual error handling might offer more direct ways.
    // For this example, let's assume 'result' can be inspected.
    if result.isError() { // Assuming 'isError()' method exists on the result type
      encounteredErrors.append(result.error()) // Assuming 'error()' method gets the error details
    } else {
      successfulResults.append(result.value()) // Assuming 'value()' method gets the success value
    }
  }
  
  successfulResults, encounteredErrors // Return both lists.
}
```
