---
title: "Your First Program: Let the Coding Magic Begin!"
linkTitle: "First Program"
description: >
  Step-by-step guide to writing, running, and totally rocking your first few Manuscript programs. Prepare for applause!
---

Alright, future code maestro, let's get your hands dirty (metaphorically, of course) and write your very first program in Manuscript! This guide will hold your hand (gently) as you create, compile, and run a simple yet thrilling Manuscript program. It's easier than you think, and way more fun!

## The Legendary "Hello, World!": Your Initiation Rite

Every grand programming adventure, from the smallest script to the most epic application, begins with a humble "Hello, World!". It's a tradition, a rite of passage, and your first taste of telling the computer what to do.

### Step 1: Create Your Spell Scroll (The File)
First, you need a place to write your magical incantations. Open your command line or terminal and type this:

```bash
touch hello.ms
```
This command creates an empty file named `hello.ms`. The `.ms` is Manuscript's special file extension – think of it as the mark of a genuine Manuscript spell scroll!

### Step 2: Inscribe the Magic Words (Write the Code)
Now, open `hello.ms` in your favorite text editor (VS Code, Sublime Text, Notepad++, even good ol' Notepad will do for now!) and type in the following lines:

```ms
// This is your main function, the grand entrance to your program!
fn main() {
  // The 'print' command tells Manuscript to display something on the screen.
  print("Hello, World! Manuscript, I have arrived!")
}
```
What's happening here?
- `fn main() { ... }` defines the **main function**. This is where every Manuscript program kicks off its adventure.
- `print(...)` is your first command! It tells the computer to display whatever text (string) you put inside the parentheses and quotes.

### Step 3: Unleash the Magic! (Run the Program)
Back in your terminal, it's time for the magic moment. Type this command and press Enter:

```bash
msc hello.ms
```
The `msc` command is the Manuscript compiler and runner. It reads your `hello.ms` file, understands your instructions, and brings them to life!

You should see this output:
```
Hello, World! Manuscript, I have arrived!
```
**BOOM!** You did it! You wrote and ran your first Manuscript program! Take a bow, accept the applause, maybe treat yourself to a cookie. You've earned it.

> Blank screen now speaks loud,
> "Hello, World!" a coder's cheer,
> Magic has begun.

## Level Up! Working with Variables

Feeling confident? Let's expand your program to use **variables**. Variables are like little labeled boxes where you can store information.

Open your `hello.ms` (or create a new file, say `variables_intro.ms`) and try this:

```ms
fn main() {
  // 'let' is how you declare a new variable.
  let name = "Manuscript" // Storing the text "Manuscript" in a box labeled 'name'
  let version = "0.1.0"    // Storing "0.1.0" in a box labeled 'version'
  
  // Now we use the '+' to stick strings together (concatenation)
  print("Hello from " + name + " version " + version + "! Isn't this cool?")
}
```
Run this program (`msc variables_intro.ms`). What do you see?

This introduces some cool new concepts:
- `let` declarations: Your keyword for creating new variables.
- String concatenation: Using `+` to join pieces of text together.
- Type inference: Notice you didn't have to tell Manuscript that `name` was text? It figured it out! Manuscript is smart like that.

## Numbers and Math: Crunching Some Digits

Manuscript isn't just about text; it's a whiz with numbers too! Let's do some basic math.

Modify your program (or create `math_fun.ms`):

```ms
fn main() {
  let x = 10
  let y = 20
  let sum = x + y // Manuscript does the addition for you!
  
  // To print numbers alongside text, we often convert them to strings.
  // The 'string()' function does exactly that!
  print("The grand sum of " + string(x) + " and " + string(y) + " is... " + string(sum) + "! Ta-da!")
}
```
Run it!

New powers unlocked:
- Integer variables: Storing whole numbers.
- Mathematical operations: `+` for addition (and it knew not to just stick "10" and "20" together this time!).
- Type conversion with `string()`: Politely asking a number to behave like text for printing.

## Functions: Your Reusable Code Spells

Imagine you have a set of instructions you need to perform often. Instead of writing them out every time, you can bundle them into a **function**!

Let's create `functions_intro.ms`:

```ms
// First, we define our reusable spell (function) called 'greet'.
// It takes one piece of information (a 'name' which must be a string).
fn greet(name string) {
  print("A joyous hello to you, " + name + "!")
}

// Now, our main function can use this 'greet' spell multiple times.
fn main() {
  greet("Alice")    // Call the greet function, passing "Alice" as the name.
  greet("Bob")      // Call it again for Bob.
  greet("Charlie")  // And one more time for Charlie!
}
```
Run this, and watch your `greet` function work its charm repeatedly!

What you've learned:
- Function definition with `fn`: How to create your own named blocks of code.
- Parameter types (`string`): Specifying what kind of "ingredients" your function expects.
- Function calls from `main()`: How to invoke your reusable spells.

## Functions That Give Back: Return Values

Not only can functions take ingredients, but they can also produce a result, called a **return value**.

Let's make an `add` function in `return_values.ms`:

```ms
// This function takes two integers (a and b) and returns an integer (their sum).
fn add(a int, b int) int { // The 'int' after parameters is the return type.
  return a + b // The 'return' keyword sends the result back to whoever called it.
}

fn main() {
  let result = add(5, 3) // Call 'add', and store its returned value in 'result'.
  print("Our 'add' function reports: 5 + 3 = " + string(result) + ". Impressive!")
}
```
Run it!

Key takeaways:
- Return type specified after parameters (`int` in this case).
- The `return` statement: How a function hands back its result.
- Using the returned value: Storing the function's output in a variable.

## Handling Life's Little Surprises: Error Handling

Sometimes, things don't go as planned (e.g., trying to divide by zero). Manuscript has a way to handle these potential "errors" using **bang functions**.

Let's try `error_handling_intro.ms`:

```ms
// This function might return an error, so it has '!' next to its return type.
fn divide(a int, b int) int! {
  if b == 0 {
    // If b is zero, we can't divide. So, we signal an error.
    return error("Cannot divide by zero, oh mighty user! That's a math no-no.")
  }
  // If b is not zero, we return the result of the division.
  return a / b
}

fn main() {
  // We 'try' to call the risky 'divide' function.
  let result = try divide(10, 2)
  print("Result of 10 divided by 2: " + string(result))
  
  print("Now, let's try something dangerous...")
  let errorResult = try divide(10, 0)
  // The 'try' expression catches the error. If you didn't 'try', and an error occurred,
  // your program might stop. 'try' gives you a chance to handle it (more on that later!).
  // For now, 'errorResult' would hold information about the error if one occurred.
  print("If divide(10,0) caused an error, 'try' helped us manage it!")
  // If you were to print errorResult and an error occurred, it would show error details.
  // If no error, it would print the value.
}
```
This is a glimpse into error handling!

What's new:
- Bang functions (`int!`): Indicate that a function might return an error.
- `if` statements: For making decisions based on conditions.
- `try` expressions: A way to call functions that might error, allowing you to handle the outcome.
- `error()` function: How you create an error to signal a problem.

## Storing Your Treasures: Basic Data Structures

Manuscript provides ways to store collections of items, like lists (arrays) and labeled containers (objects).

Let's explore in `data_structures_intro.ms`:

```ms
fn main() {
  // An array: an ordered list of items.
  let numbers = [10, 20, 30, 40, 50] // An array of integers.

  // An object: a collection of key-value pairs.
  let person = { name: "Alice", age: 30, city: "Wonderland" }
  
  print("The first number in our list is: " + string(numbers[0])) // Accessing array items by index (starts at 0!)
  print(person.name + " is " + string(person.age) + " years old and lives in " + person.city + ".") // Accessing object fields using '.'
}
```
Run this to see how you can access your stored treasures!

You've just learned about:
- Array literals `[1, 2, 3]`: How to define a list of items.
- Object literals `{ key: value }`: How to define a container with named fields.
- Array indexing `numbers[0]`: Getting items from an array by their position.
- Object field access `person.name`: Getting values from an object using their field names.

## Fancy Text: String Interpolation

Remember how we used `+` to join strings and converted numbers to strings? Manuscript has an even slicker way called **string interpolation**.

Try this in `interpolation_intro.ms`:

```ms
fn main() {
  let name = "World"
  let count = 42
  // Use ${variable_name} right inside a double-quoted string!
  print("Hello, ${name}! The current magic count is: ${count}. Neat, huh?")
}
```
So much cleaner! Manuscript automatically converts `count` to a string within the interpolated string.

## Declaring in Bulk: Block Variable Declarations

If you have a group of variables to declare, you can do it all in one go with a block.

Let's try `block_vars.ms`:

```ms
fn main() {
  let ( // Start a block declaration
    appName = "My Super Manuscript App"
    appVersion = "1.0-alpha"
    isReleased = false // Not yet, but soon!
  )
  
  print("Welcome to ${appName} version ${appVersion}. Released: ${isReleased}.")
}
```
This can make your declarations neat and tidy, especially for related variables.

## Onwards, Brave Coder! Next Steps on Your Epic Journey!

Whew! You've just learned a TON. From a simple "Hello, World!" to functions, error handling, and data structures – you're well on your way to becoming a Manuscript aficionado!

So, what's next on this grand adventure?

1.  **[Understand Manuscript's Philosophy (Language Overview)](../overview/)**: Get a deeper insight into why Manuscript is designed the way it is. It's like learning the lore behind the magic system!
2.  **[Explore More Language Features](../../constructs/)**: Ready to dive deeper into specific spells and constructs? This is your advanced grimoire.
3.  **[Consult the Ancient Scrolls (Reference)](../../reference/)**: For the nitty-gritty details of syntax and language elements, the reference guide is your ultimate source of truth.

## Common Spells and Incantations (Patterns)

As you continue your journey, you'll notice some patterns emerging. Here are a few common ones you've already touched upon:

### Working with Collections (like Arrays)
Looping through items in a list is super common.

```ms
fn main_collections_pattern() {
  let items = ["apple", "banana", "cherry", "date"]
  
  // 'for item in items' is a common way to loop through each element.
  for item in items {
    print("Current delightful fruit: " + item)
  }
}
```

### The "Try, Try Again" Error Handling Pattern
A common way to use functions that might error.

```ms
fn processData(input string) string! { // This function can error!
  if input == "" {
    return error("Input cannot be an empty void, please provide data!")
  }
  // Let's pretend it processes the data by making it uppercase.
  return input.upper()
}

fn main_error_pattern() {
  let result = try processData("hello manuscript") catch "default_value_on_error"
  // If processData succeeds, 'result' gets the uppercased string.
  // If it errors (e.g., if we passed ""), 'result' gets "default_value_on_error".
  print("Processed data (or default): " + result)

  let anotherResult = try processData("") catch {
    print("Caught an error during processing! Using a fallback.")
    "fallback after logging"
  }
  print("Another result: " + anotherResult)
}
```

### Defining Your Own Data Blueprints (Type Definitions)
Creating your own custom types is a cornerstone of building bigger applications.

```ms
// Define a blueprint for what a 'Person' looks like.
type Person {
  name string
  age int
  hasCoolHat bool
}

fn main_type_pattern() {
  // Create an instance of our Person blueprint.
  let alice = Person{
    name: "Alice the Awesome",
    age: 30,
    hasCoolHat: true // Of course!
  }
  
  print(alice.name + " is " + string(alice.age) + " and their hat status is: " + string(alice.hasCoolHat))
}
```

The most important next step? **Keep experimenting!** The best way to learn Manuscript (or any language) is by writing code, trying things out, making mistakes (everyone does!), and learning from them.

Happy coding, and may your bugs be few and your logic flawless!
