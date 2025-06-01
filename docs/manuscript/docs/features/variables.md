---
title: "Variables: Naming Your Data Pets"
linkTitle: "Variables"

description: >
  Declaring variables with 'let', understanding Manuscript's type system (it's smarter than you think!), and keeping your data in the right enclosures (scope).
---

Welcome to the wonderful world of variables! In Manuscript, as in any good programming language, variables are how you give names to your data, so you can refer to it, change it, and generally boss it around. Think of them as labeled boxes, or perhaps, data pets that you get to name. We use the trusty `let` keyword to bring these variables into existence. Manuscript is also pretty clever with **type inference** (guessing the data type), but it appreciates it when you're explicit too with **type annotations**.

## Basic Variable Declaration: Let There Be Data!

This is where the magic begins – giving your data a name and a cozy spot to live.

### Simple Variables: The Usual Suspects
Here's how you declare variables. Manuscript often figures out the type on its own (isn't that nice?).

```ms
let name = "Alice"        // Manuscript correctly infers this is a 'string' of text.
let age = 25              // And this is an 'int' (a whole number).
let height = 5.9          // This looks like a 'float' (a number with a decimal).
let active = true         // A 'bool' (true or false). Elementary, my dear Watson!
```

### With Type Annotations: Being Extra Clear
Sometimes you want to be explicit about the type, or Manuscript needs a hint. That's what type annotations are for.

```ms
let name string = "Alice"   // "I insist, this 'name' is a string!"
let age int = 25            // "Make no mistake, 'age' is an integer."
let height float = 5.9      // "Indeed, 'height' is a float."
let active bool = true      // "Verily, 'active' is a boolean."
```

### Uninitialized Variables: Boxes Waiting to Be Filled
You can declare a variable now and give it a value later. If you declare its type, it knows what kind of data to expect.

```ms
let x int                 // 'x' is declared as an int, but has no value yet. It's patiently waiting.
let y                     // 'y' is declared, but untyped and uninitialized. A bit of a mystery!
                          // (Use with caution, often better to initialize or type).
```
> With a simple `let`,
> Data gets a name, a home,
> Code starts to make sense.

## Number Literals: Speaking in Digits

Manuscript understands numbers in various fancy dress costumes.

```ms
let decimal = 42          // Your standard, everyday decimal integer.
let binary = 0b1010       // Binary! This is 10 in decimal. For the 1s and 0s enthusiast.
let hex = 0xFF            // Hexadecimal! This is 255 in decimal. Looks cool, right?
let octal = 0o755         // Octal! This is 493 in decimal. A bit old-school, but supported.
let pi = 3.14159          // Floating point numbers, for when things get fractional.
```

## String Literals: Weaving Words and Text

Textual data (strings) can also be declared in a few ways.

### Single Quotes: Simple and Sweet
For straightforward text.

```ms
let message = 'Hello, World! Isn''t this nice?' // Use '' for a literal single quote inside.
let path = 'C:\Users\alice\documents'          // Often used for paths, though be mindful of escapes.
```

### Double Quotes: The Flexible Friend
Similar to single quotes, but often preferred, especially when you need interpolation.

```ms
let message = "Hello, World! Manuscript is fun."
let template = "Welcome, ${name}! We've been expecting you." // See interpolation below!
```

### Multi-line Strings: For Poems, Epics, and Giant Configurations
When your text spans multiple lines, triple quotes (single or double) are your pals.

```ms
let poem = '''
Roses are red,
Violets are blue,
Manuscript makes coding
A delight for you.
''' // Aww.

let config = """
{
  "appName": "My Awesome App",
  "version": "1.0.0",
  "featureFlags": {
    "newShinyFeature": true
  }
}
""" // Perfect for embedding JSON or other structured text.
```

### String Interpolation: Weaving Variables into Your Text
This is super handy. Embed variables directly within a string (usually double-quoted or triple-double-quoted) using `${variableName}`.

```ms
let userName = "Alice" // Corrected variable name for clarity
let userAge = 25     // Corrected variable name for clarity
let greeting = "Hello, ${userName}! In dog years, you are ${userAge * 7}." // Math in interpolation!
// greeting will be "Hello, Alice! In dog years, you are 175."
```

## Special Values: The Null and the Void

Sometimes you need to represent nothingness or the absence of a value.

```ms
let empty = null          // 'null' often means "no value here" or "this variable isn't pointing to anything."
let nothing = void        // 'void' typically represents the absence of a return value from a function,
                          // or can be a type for a variable that holds no meaningful data.
```

## Block Variable Declarations: Declaring a Whole Squad at Once

Got a group of related variables? You can declare them together in a block.

```ms
// Declaring a group of variables, their types are inferred.
let (
  name = "Alice"
  age = 25
  city = "New York"
  country = "USA" // Added for fun
)
// print(name + " from " + city + ", " + country)
```

### Mixed Types in Block: Still Works!
You can also include type annotations within a block declaration.

```ms
let (
  count int = 0
  message string = "Processing started..."
  ready bool = false
  progress float = 0.0 // Why not?
)
// print(message + " Progress: " + string(progress) + "%")
```

## Destructuring Assignment: Unpacking Your Data Presents!

Destructuring is a cool way to extract values from objects or arrays directly into variables. It's like opening a gift box and neatly placing each item where it belongs.

### Object Destructuring: Raiding the Object's Goodies
Pluck out specific fields from an object (or a map-like structure).

```ms
let person = { name: "Alice", age: 25, occupation: "Wizard" }

// Extract 'name' and 'age' into their own variables.
let { name, age } = person
// Now, 'name' is "Alice" and 'age' is 25. 'occupation' is still in 'person'.
// print(name + " is " + string(age) + " years old.")
```

### Array Destructuring: Cherry-Picking from the List
Similarly, pull out items from an array by their position.

```ms
let coordinates = [10, 20, 30] // A 3D point, perhaps?

// Extract the first two elements into 'x' and 'y'.
let [x, y] = coordinates
// 'x' is 10, 'y' is 20. The '30' is still in 'coordinates[2]'.
// print("Point x: " + string(x) + ", y: " + string(y))
```

### Block Destructuring: Combining Unpacking Power
You can even destructure within a block declaration, often from function calls that return objects or arrays.

```ms
// Assume getPerson() returns an object like { name: "Bob", age: 42 }
// Assume getCoordinates() returns an array like [100, 200]
/*
let (
  { name, age } = getPerson()     // Destructure the object from getPerson()
  [x, y] = getCoordinates() // Destructure the array from getCoordinates()
)
print(name + " is at coordinates: " + string(x) + "," + string(y))
*/
```

## The Manuscript Type System: Understanding Your Data's DNA

Manuscript needs to know what *kind* of data your variables are holding. This is where the type system comes in.

### Basic Types: The Fundamental Building Blocks
- `int` - For whole numbers (e.g., -5, 0, 42).
- `float` - For numbers with decimal points (e.g., 3.14, -0.001).
- `string` - For sequences of text characters (e.g., "Hello!", 'Open sesame!').
- `bool` - For truth values, which can only be `true` or `false`.

### Collection Types: Holding Groups of Things
- `string[]` - An array (list) containing strings.
- `int[]` - An array of integers.
- `CustomType[]` - An array of your very own custom-defined types! (More on custom types elsewhere).

### Type Inference: Manuscript's Psychic Abilities
Often, Manuscript can figure out the type of a variable just by looking at the value you assign it. This is called type inference. It's like Manuscript is saying, "Aha! That looks like a number, so I'll call it an `int`."

```ms
let count = 42           // "Clearly an int," says Manuscript.
let message = "hello"    // "Definitely a string."
let items = [1, 2, 3]    // "An array of ints, I presume." (Correctly infers int[])
```

### Explicit Types: When You Need to Be the Boss
Sometimes, type inference isn't enough, or you want to be absolutely clear. This is especially true for empty collections or variables initialized with `null`.

```ms
let numbers int[] = []   // An empty array needs an explicit type. Otherwise, how would Manuscript know
                         // if it's for ints, strings, or rubber chickens?
let result any = null    // 'any' is a special type that can hold anything. If 'result' should later
                         // hold a specific type, you might annotate it, e.g., 'let result User = null'.
```

## Variable Scope: Where Your Data Pets Are Allowed to Roam

A variable's "scope" defines where in your code that variable is visible and can be used. Generally, variables are only accessible within the block of code (curly braces `{}`) where they are declared.

```ms
fn main_scope_example() {
  let outer = "I'm an outer variable, visible far and wide (within main_scope_example)."
  
  if true { // This 'if' creates a new, inner scope.
    let inner = "I'm an inner variable, a bit shy, only visible inside this 'if' block."
    print(outer)  // Works! Inner scopes can see variables from their outer scopes.
    print(inner)  // Works! We're in the same scope where 'inner' was born.
  }
  
  // print(inner)  // ERROR! 'inner' is out of scope here. Its block has ended.
                  // It's like trying to find a cat that only lives in the living room,
                  // but you're looking in the garden.
  print(outer)    // This still works, 'outer' is still in scope.
}
```

## Naming Conventions: How to Name Your Variables So They Don't Get Lost (and So Others Like You)

Good naming makes your code easier to read and understand. Manuscript programmers generally follow these conventions:

- **Variables**: Use `camelCase` (e.g., `userName`, `totalAmount`, `remainingLives`). The first word is lowercase, subsequent words are capitalized.
- **Constants**: For values that are meant to be constant, use `UPPER_CASE_WITH_UNDERSCORES` (e.g., `MAX_USERS`, `DEFAULT_GREETING_MESSAGE`).
- **Booleans**: Make them sound like questions or states (e.g., `isActive`, `hasPermission`, `isEmpty`).

## Examples from the Wild: Variables in Action

### Configuration Variables: Setting Up Your Program's Dashboard
```ms
// A block of configuration settings for an application.
let (
  apiUrl string = "https://api.myawesomeapp.com/v2"
  timeoutMilliseconds int = 5000 // It's good to be specific with units!
  numberOfRetries int = 3
  enableDebuggingMode bool = false // Starts false, maybe changed later.
)
// print("Connecting to: " + apiUrl)
```

### Processing Data: Manipulating Text
```ms
let inputText = "  Hello, Manuscript World!  " // Some text with extra spaces.
let trimmedText = inputText.trim()        // Removes leading/trailing whitespace.
let textLength = trimmedText.length()     // Gets the length of the trimmed string.
let uppercaseText = trimmedText.upper()   // Converts to "HELLO, MANUSCRIPT WORLD!"
let wordsArray = trimmedText.split(" ")   // Splits into an array of strings: ["Hello,", "Manuscript", "World!"]
// print("Words: " + string(wordsArray))
```

### Working with Numbers: Crunching Those Digits
```ms
let itemPrice = 19.99
let salesTaxRate = 0.08 // 8% sales tax
let finalPrice = itemPrice * (1.0 + salesTaxRate) // Calculate price with tax.
let roundedPrice = round(finalPrice, 2) // Assuming 'round(value, decimals)' exists.
                                        // Or perhaps just 'finalPrice.round(2)'
// print("Final rounded price: $" + string(roundedPrice))
```
