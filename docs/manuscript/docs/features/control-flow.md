---
title: "Control Flow: Directing Your Code's Symphony"
linkTitle: "Control Flow"

description: >
  Mastering conditional statements, loops, pattern matching, and other ways to tell your Manuscript code what to do, when, and how often.
---

Welcome, aspiring Code Conductors! Manuscript provides a rich orchestra of constructs for telling your program where to go, what to do when it gets there, and how many times to repeat the encore. Let's explore conditionals, loops, the ever-so-clever pattern matching, and statements that let you gracefully (or abruptly) change course.

## Conditional Statements: The Art of Making Choices

Life is full of choices, and so is code. Conditional statements let your program react intelligently to different situations.

### If Statements: The Basic "What If"
The simplest way to say, "If this is true, do that."

```ms
let age = 18

if age >= 18 {
  print("Congratulations, you're an adult! (Handle with care.)")
}
```

### If-Else: The "This or That" (or Even "This, That, or The Other Thing")
For when you have multiple paths your code might take.

```ms
let score = 85

if score >= 90 {
  print("A grade! You're basically a genius.")
} else if score >= 80 {
  print("B grade! Solidly impressive.")
} else if score >= 70 {
  print("C grade! You're in the game.")
} else {
  print("Below C grade. More coffee and practice, perhaps?")
}
```

### Inline Conditionals: Quick Decisions, Express Lane
For when your if-else is so simple, it fits on one line. Terse and elegant!

```ms
let age = 20 // Let's assume age is defined
let status = if age >= 18 { "adult, officially" } else { "minor, enjoy it" }
let message = if score > 85 { "Outstanding performance!" } else { "Keep up the good work!" } // And score too
```

## Loops: For When You're Feeling Repetitive (In a Good Way)

Need to do something over and over? Loops are your best friends. They never get bored!

### For Loops: The Workhorse of Repetition

#### Traditional For Loop: The Classic Counter
Old school, but sometimes it's just what you need to count your way through iterations.

```ms
for let i = 0; i < 10; i = i + 1 {
  print("Counting sheep, number: " + string(i)) // Hopefully not putting your CPU to sleep
}
```

#### For-In Loop (Arrays): Strolling Through Collections
The most civilized way to visit each item in an array.

```ms
let numbers = [1, 2, 3, 4, 5] // A fine collection of digits

for num in numbers {
  print("Behold, the number: " + string(num))
}
```

#### For-In Loop (Objects): Peeking into Properties
Iterate over the keys of an object. What treasures will you find?

```ms
let person = { name: "Alice", age: 30, city: "New York" } // Our esteemed subject

for key in person {
  // person[key] fetches the value associated with the current key
  print(key + " holds the value: " + string(person[key]))
}
```

#### For-In Loop with Index: Knowing Your Place
Sometimes you need the item *and* its position in line.

```ms
let items = ["apple", "banana", "cherry"] // A healthy assortment

for i, item in items {
  print("Item at position " + string(i) + " is a delicious " + item)
}
```

### While Loops: Repeating Until Further Notice
Keep looping as long as a condition stays true. Don't forget to change the condition, or you'll loop forever (an infinite loop party is rarely fun).

```ms
let count = 0

while count < 5 {
  print("Current 'while' loop count: " + string(count))
  count = count + 1 // Crucial step to avoid eternal looping!
}
```

### Loop Control: Being the Boss of Your Loops

Sometimes you need to change a loop's behavior mid-stride.

#### Break Statement: "I'm Outta Here!"
Jump out of a loop entirely, no questions asked.

```ms
for i in range(10) { // Assuming range(10) gives 0 through 9
  if i == 5 {
    print("Five is enough for me!")
    break // Exit the loop immediately
  }
  print(i)
}
// Prints: 0, 1, 2, 3, 4, and then "Five is enough for me!"
```

#### Continue Statement: "Skip This One!"
Stop the current iteration and jump to the next one.

```ms
for i in range(10) {
  if i % 2 == 0 { // If i is even...
    print("Skipping even number: " + string(i))
    continue // ...skip the rest of this iteration
  }
  print("Processing odd number: " + string(i)) // This only runs for odd numbers
}
// Prints: Processing odd number: 1, Processing odd number: 3, etc.
```
> Path divides in two,
> Code must choose, then choose again,
> Logic finds its way.

## Pattern Matching: The Art of Elegant Interrogation

Manuscript's `match` expressions are like a Swiss Army knife for handling multiple conditions, types, and structures in a super readable way.

### Basic Match: Simple Case-by-Case
Like a switch statement, but with more flair.

```ms
let value = 42

let result = match value {
  0: "it's zero"
  1: "it's one"
  42: "it's THE answer to everything"
  default: "it's something else, a mystery!"
}
// result will be "it's THE answer to everything"
```

### Match with Conditions: Ranges and More
You can use ranges and other conditions within your cases.

```ms
let score = 85

let grade = match score {
  90..100: "A (Absolutely Awesome!)"
  80..89: "B (Brilliantly Done!)"
  70..79: "C (Certainly Competent!)"
  60..69: "D (Don't Despair!)"
  default: "F (Future Opportunities Abound!)"
}
// grade will be "B (Brilliantly Done!)"
```

### Match with Types: What Kind of Thing Is This?
Check the type of a variable and act accordingly.

```ms
fn processValue(value any) string { // 'any' means it could be, well, anything
  return match value {
    int: "A whole number, I see: " + string(value)
    string: "Some text! It says: " + value
    bool: "A boolean value: " + string(value)
    default: "I'm stumped. It's some other type."
  }
}
```

### Match with Destructuring: Unpacking Your Data Mid-Match
Pull apart objects or arrays directly within the match cases. Super handy!

```ms
let point = { x: 10, y: 20 }

let description = match point {
  { x: 0, y: 0 }: "It's at the origin, the very beginning!"
  { x: 0, y }: "On the y-axis, at the lofty height of " + string(y)
  { x, y: 0 }: "On the x-axis, at the distinguished position of " + string(x)
  { x, y }: "Just a regular point at (" + string(x) + "," + string(y) + "), doing its thing."
}
// description will be "Just a regular point at (10,20), doing its thing."
```

### Match with Code Blocks: When One Line Isn't Enough
Sometimes, a case needs to do more than just return a value.

```ms
let status = "error"

match status {
  "success" {
    print("Hooray! Operation completed successfully.")
    updateProgress(100) // Let's imagine these functions exist
  }
  "error" {
    print("Uh oh. An error occurred. Details have been logged (somewhere).")
    logError("Operation failed spectacularly")
  }
  "pending" {
    print("Still chugging along... Operation in progress.")
    showSpinner() // Engage the spinny thing!
  }
  default {
    print("Received an unknown status: " + status + ". How curious.")
  }
}
```

## Try-Catch: Gracefully Handling Potential Mishaps (Error Handling)

Not strictly control flow in the "if/else/loop" sense, but `try` and `catch` profoundly affect how your code flows when errors pop up.

### Try Expressions: "Attempt This, But Be Cool If It Fails"
If `parseNumber` might throw an error, `try` lets the error propagate up, or you can catch it.

```ms
// Assume parseNumber(text) returns a number or throws an error
let result = try parseNumber("42")
// If parseNumber("42") succeeds, result gets the number.
// If it fails, the current function might stop and pass the error to its caller.
```

### Try with Default: "Try This, Or Use This Backup Plan"
If the risky operation fails, `catch` provides a default value, and life goes on.

```ms
let result = try parseNumber("invalid_input") catch 0
// result becomes 0 because "invalid_input" probably isn't a valid number.
// No error propagation here, just a smooth recovery.
```

### Check Statements: "Ensure This Is True, Or Bail Out"
A `check` statement verifies a condition. If false, the current function exits. It's a bit like an assertion that controls flow.

```ms
fn processFile(filename string) {
  // These are hypothetical functions for the example
  // check fileExists(filename)  // If false, function exits here
  // check isReadable(filename)  // If false, function also exits here
  
  print("File ${filename} seems okay. Proceeding with gusto!")
  // Continue processing...
}
```

## Early Exit Statements: Making a Swift Departure

Sometimes you know the answer before the function is done.

### Return: "My Work Here Is Done"
The classic way to exit a function and optionally give back a value.

```ms
fn validateAge(age int) bool {
  if age < 0 {
    print("Ages usually aren't negative, just sayin'.")
    return false // Exit early
  }
  
  if age > 150 {
    print("Impressive longevity! But perhaps a typo?")
    return false // Exit early
  }
  
  return true // All checks passed!
}
```

### Yield (for generators): "Here's One Value, More Coming Soon!"
Used in generator functions to produce a sequence of values one at a time. (A bit more advanced, but good to know it exists!)

```ms
fn generateNumbers() { // This would be a generator function
  for i in range(5) {
    yield i * 2 // Send back one value, then pause until the next is requested
  }
}
// Calling this would require a loop or other construct to consume the yielded values.
```

### Defer: "I'll Do This Later, Promise!"
Schedule a statement to be executed just before the function exits, no matter how it exits (normal return, error, etc.). Super useful for cleanup.

```ms
fn processFile(filename string) {
  // let file = openFile(filename) // Imagine this opens a file
  // defer file.close()  // "No matter what happens, close this file when we're done."
  
  print("Processing ${filename}... pretending it's a very important file.")
  // Process file...
  // Even if an error happens here, file.close() would be called.
  print("Finished with ${filename}. 'defer' will handle cleanup.")
}
```

## Guard Clauses: The Bouncers of Your Function

Use guard clauses at the beginning of your function to check for invalid inputs or conditions and exit early. Keeps your main logic clean.

```ms
fn calculateDiscount(price float, customerType string) float! { // The '!' means it can return an error
  // Guard clauses: "You shall not pass (with bad data)!"
  if price <= 0 {
    return error("Price must be a positive value, my friend.")
  }
  
  if customerType == "" {
    return error("Customer type cannot be an empty mystery.")
  }
  
  // Main logic, now that we know the inputs are sane:
  return match customerType {
    "premium": price * 0.15
    "regular": price * 0.10
    "new": price * 0.05
    default: 0.0 // No discount for unknown types, alas.
  }
}
```

## Nested Control Flow: Weaving Complex Tapestries

You can, and often will, combine these constructs. Loops inside ifs, matches inside loops... it's a control flow party!

```ms
fn processData(items any[]) { // An array of 'any' type
  for item in items {
    if item == null {
      print("Skipping a null item. Nothing to see here.")
      continue // Move to the next item
    }
    
    match typeof(item) { // typeof() is hypothetical, actual type checking may vary
      "string" {
        if item.length() > 0 { // Assuming item is known to be a string here
          print("Processing non-empty string: " + item)
        } else {
          print("Encountered an empty string. So quiet.")
        }
      }
      "int" { // Assuming item is known to be an int here
        if item > 0 {
          print("Positive integer found: " + string(item) + ". Counting up to it:")
          for i in range(item) { // Loop within a match case!
            print("Step " + string(i))
          }
        } else {
          print("Integer is not positive: " + string(item))
        }
      }
      default {
        print("Unknown type, playing it safe and skipping.")
        continue
      }
    }
  }
}
```

## Sage Advice: Best Practices for Flowing Control

A few tips from the wise old programmers of yore (and today).

### Readability is Your Guiding Star
- Use descriptive variable names in loops (e.g., `user` instead of `x` in `for user in users`).
- Prefer `for-in` loops for collections; they're often clearer than manual index management.
- Employ guard clauses to reduce deep nesting in your functions. Flatter is often better!

### Performance Considerations (When Seconds Count)
- Use `break` and `continue` to bail out of loops early if you've found what you need or know the rest is irrelevant.
- `match` can sometimes be more efficient (and readable) than a long chain of `if-else if` statements, especially if the compiler can optimize it well.

### Error Handling: Expect the Unexpected
- Embrace `try` expressions for operations that might throw a wrench in the works.
- `defer` is your best friend for cleanup tasks (closing files, releasing resources, etc.).
- Validate inputs at the beginning of your functions (guard clauses again!).

### Pattern Matching Prowess
- Use `match` for complex conditional logic; it can make intricate decisions surprisingly clear.
- Leverage destructuring within `match` cases for elegant access to parts of your data.
- Always consider a `default` case in your `match` statements to handle anything unexpected. It's like a safety net for your logic.
