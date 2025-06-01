---
title: "Variables & Types: Giving Your Data a Name and a Purpose"
linkTitle: "Variables and Types"

description: >
  Learn the fine art of declaring variables, wrangling data types, and appreciating Manuscript's occasional mind-reading via type inference.
---

So, you want to store data? Excellent choice! In Manuscript, as in most civilized programming languages, we use **variables**. Think of them as labeled boxes where you can keep your digital doodads. To declare these boxes, Manuscript employs the `let` keyword. It's also pretty smart about guessing types (that's **type inference**), but it appreciates it when you're explicit too.

## Declaring Your Intentions (Variable Declaration)

### The Basic "Let There Be Data"

Use `let` and give your data a home:

```ms
fn main() {
  let name = "Alice"      // A string of characters, perhaps a name
  let age = 25            // An integer, representing years of wisdom (or not)
  let height = 5.6        // A float, for when precision matters
  let active = true       // A boolean, the light switch of data
  
  print("Name: " + name)
  print("Age: " + string(age)) // We need to convert numbers to strings to print them nicely
}
```

### Manuscript: The Mind Reader (Type Inference)

Manuscript often deduces the type from the value you provide. Clever, eh?

```ms
fn main() {
  let message = "Hello"        // Clearly, this is text, so: string
  let count = 42              // Looks like a whole number: int
  let price = 19.99           // Decimal point? Must be a float
  let ready = true            // True or false? That's a bool's job
  let data = null             // The void, the emptiness... a null type
}
```
> Empty box holds much,
> Code gives it a name and form,
> Data comes alive.

### Stating the Obvious (Explicit Types)

Sometimes, you want to be crystal clear, or the context requires it. Manuscript respects your explicitness:

```ms
fn main() {
  let name string = "Alice"   // "I insist this is a string!"
  let age int = 25            // "And this, an integer!"
  let height float = 5.6      // "A float, no doubt!"
  let active bool = true      // "Indubitably, a boolean!"
}
```

## The Many Flavors of Data (Data Types)

### Numbers: The Building Blocks

#### Integers: Wholesome Numbers
For when you don't need fractions.

```ms
fn main() {
  // Basic integers
  let positive = 123
  let negative = -456
  let zero = 0
  let large = 9876543210 // Manuscript handles big numbers too!
  
  // From expressions, because math is fun
  let sum = 10 + 20
  let difference = 100 - 50
  
  print("Sum: " + string(sum))
}
```

#### Numbers from Other Dimensions (Bases)
For the discerning programmer who enjoys a bit of binary, hex, or octal.

```ms
fn main() {
  let binary = 0b1010      // Binary (that's 10 to us decimal folk)
  let hex = 0xFF           // Hexadecimal (255, looking fancy)
  let octal = 0o777        // Octal (511, for old-school charm)
  
  print("Binary: " + string(binary))
  print("Hex: " + string(hex))
  print("Octal: " + string(octal))
}
```

#### Floating Point Numbers: For the Fractional World
When integers just don't cut it.

```ms
fn main() {
  let positive = 1.23
  let negative = -0.005
  let zero = 0.0         // Zero, but with a floating point attitude
  let noLeading = .5       // Same as 0.5, for the minimalist
  
  // Expressions, again!
  let sum = 0.5 + 1.2
  let quotient = 10.0 / 4.0 // Division often results in floats
  
  print("Quotient: " + string(quotient))
}
```

### Strings: Weaving Words
For text, glorious text.

#### Basic Strings: Quotes Galore
Single or double, Manuscript isn't picky.

```ms
fn main() {
  let singleQuoted = 'Hello, World!'
  let doubleQuoted = "Hello, World!" // Choose your fighter
  
  print(singleQuoted)
  print(doubleQuoted)
}
```

#### Multi-line Strings: When You Have a Lot to Say
For poems, manifestos, or very long error messages.

```ms
fn main() {
  let multiLine = '''
This is a multi-line string.
It can span several lines without complaint.
Quite handy for embedding longer texts.
'''
  
  let multiDouble = """
Another way to do multi-line,
if you prefer your quotes doubled.
Consistency is a virtue, usually.
"""
  
  print(multiLine)
}
```

#### String Interpolation: Weaving Variables into Text
Like mail merge, but for programmers. Say goodbye to endless string concatenation!

```ms
fn main() {
  let name = "Alice"
  let age = 25
  
  // Notice the ${variable} syntax. Smooth!
  let greeting = "Hello, ${name}! You are ${age} years old."
  print(greeting)
  
  // Works with expressions too, because why not?
  let message = "In 5 years, you'll be ${age + 5}. Time flies!"
  print(message)
}
```

### Booleans: The Arbiters of Truth
True or false. Yes or no. On or off. Simple, yet powerful.

```ms
fn main() {
  let isTrue = true
  let isFalse = false
  
  // Often born from comparisons
  let isAdult = age >= 18  // Assuming 'age' is defined elsewhere, of course
  let isEqual = 10 == 10 // Profound, isn't it?
  let isGreater = 10 > 5
  
  print("Is adult: " + string(isAdult))
}
```

### Null and Void: The Great Emptiness
`null` means "there's a box, but it's empty." `void` often means "this function doesn't give anything back."

```ms
fn main() {
  let empty = null         // Represents the intentional absence of a value
  let nothing = void       // Often used to signify no return from a function
                           // (though assigning it like this is less common for void)
  
  print("Empty: " + string(empty)) // Printing null is often... null.
}
```

## Fancy Moves: Advanced Variable Declarations

### Block Declarations: Declaring en Masse
For when you have a group of related variables.

```ms
fn main() {
  let (
    username = "alice"
    password = "superSecretPassword123" // Shh!
    active = true
    attempts = 0
  )
  
  print("User: " + username)
  print("Active: " + string(active))
}
```

### Destructuring Objects: Raiding the Treasure Chest
Pluck out the specific bits you need from an object.

```ms
fn main() {
  let person = {
    name: "Alice"
    age: 30
    city: "New York"
  }
  
  // "I'll take 'name' and 'age', thank you very much!"
  let {name, age} = person
  
  print("Name: " + name)
  print("Age: " + string(age))
}
```

### Destructuring Arrays: Cherry-Picking from a List
Similar to object destructuring, but for ordered collections.

```ms
fn main() {
  let coordinates = [10, 20]
  let colors = ["red", "green", "blue"]
  
  let [x, y] = coordinates           // First becomes x, second becomes y
  let [first, second, third] = colors
  
  print("X: " + string(x) + ", Y: " + string(y))
  print("First color: " + first)
}
```

### Complex Destructuring: Show Off Your Skills
Combine these techniques for maximum data-extraction efficiency.

```ms
fn main() {
  let (
    name = "Alice"
    age = 30
    {city, country} = {city: "NYC", country: "USA"} // Destructure an inline object
    [r, g, b] = [255, 128, 64]                      // Destructure an inline array
  )
  
  print("${name} lives in ${city}, ${country}")
  print("Color: rgb(${r}, ${g}, ${b})")
}
```

## Changing Your Mind (Variable Assignment)

### Basic Assignment: New Value, Who Dis?
Variables can, well, vary. Change their contents with `=`.

```ms
fn main() {
  let count = 0
  print("Initial count: " + string(count))

  count = 10 // "I've decided count should be 10 now."
  print("After change: " + string(count))
  
  count = count + 5 // Use its own value in a new assignment
  print("After increment: " + string(count))
}
```

### Compound Assignment: The Shortcut Lane
For when you're too busy to type `variable = variable + something`.

```ms
fn main() {
  let x = 10
  
  x += 5     // Equivalent to: x = x + 5. Now x is 15.
  x -= 3     // Equivalent to: x = x - 3. Now x is 12.
  x *= 2     // Equivalent to: x = x * 2. Now x is 24.
  x /= 4     // Equivalent to: x = x / 4. Now x is 6.
  x %= 3     // Equivalent to: x = x % 3. Now x is 0 (remainder of 6/3).
  
  print("Final x: " + string(x))
}
```

## Type Conversion: Making Data Play Nice

Sometimes, you have a number but need text, or vice-versa.

### Explicit Conversion: "I Command Thee, Change Form!"
Tell Manuscript exactly what you want.

```ms
fn main() {
  let age = 25
  let price = 19.99
  let active = true
  
  // Convert to string (essential for printing with other strings)
  let ageStr = string(age)
  let priceStr = string(price)
  let activeStr = string(active)
  
  // Convert between numbers
  let ageFloat = float(age)      // 25 becomes 25.0
  let priceInt = int(price)      // 19.99 becomes 19 (decimal part is rudely truncated)
  
  print("Age as string: " + ageStr)
  print("Price as int (beware truncation!): " + string(priceInt))
}
```

### Parsing from Strings: From Text to Reality
When you have data as text (e.g., user input) and need it as a number or boolean.

```ms
fn main() {
  let numberStr = "42"
  let floatStr = "3.14"
  let boolStr = "true"
  
  let number = parseInt(numberStr)       // "42" the text becomes 42 the number
  let decimal = parseFloat(floatStr)   // "3.14" becomes 3.14
  let flag = parseBool(boolStr)        // "true" becomes true

  // What if parsing fails? Manuscript might return null or throw an error.
  // Always good to be prepared for stubborn text that refuses to convert.
  
  print("Parsed number: " + string(number))
  print("Parsed float: " + string(decimal))
  print("Parsed bool: " + string(flag))
}
```

## Variable Scope: Where Does My Data Live?

Not all variables are accessible from everywhere. Scope defines a variable's lifespan and visibility.

### Function Scope: Local Heroes
Variables declared inside a function are its loyal subjects and don't venture outside.

```ms
fn demonstrate() {
  let localVar = "I'm a local legend (within demonstrate)"
  print(localVar)
}

fn main() {
  let mainVar = "I'm famous (within main)"
  demonstrate()
  
  // Trying to print localVar here would cause a ruckus (error).
  // It's out of its jurisdiction.
  print(mainVar)
}
```

### Block Scope: Even More Localized
Variables declared within curly braces `{}` (a block) are confined to that block.

```ms
fn main() {
  let outer = "I'm an outer-worlder"
  
  { // This is a block. Think of it as a private club.
    let inner = "I'm an inner-circle member"
    print(outer)  // Outer variables are usually visible to inner scopes.
    print(inner)  // Of course, inner can see its own.
  } // End of the club. 'inner' vanishes in a puff of logic.
  
  print(outer)    // 'outer' is still here, unfazed.
  // print(inner) // ERROR! 'inner' is unknown in this realm.
}
```

## Best Practices: The Path to Code Zen

A few tips to keep your code clean and your sanity intact.

### Use Descriptive Names: Clarity is King
Your future self (and your colleagues) will thank you.

```ms
fn main() {
  // Yes, please!
  let userAge = 25
  let isAccountActive = true
  let shoppingCartTotal = 99.99
  
  // Oh, dear. No.
  let a = 25     // 'a' for... age? amount? aardvark?
  let flag = true  // Flag for what? Danger? Fun?
  let x = 99.99  // The eternal mystery of 'x'.
}
```

### Use Type Annotations for Clarity (When Needed)
If Manuscript's mind-reading isn't obvious, lend it a hand.

```ms
fn main() {
  // Good for complex types or when the initial value is ambiguous
  let users []User = [] // An empty array, but of what? Ah, Users!
  let config Config = loadDefaultConfig() // What does this function return? A Config object!
  let timeout int = 30 // Is this 30 milliseconds? Seconds? Explicit 'int' helps,
                       // though a comment explaining 'seconds' is even better.
}
```

### Group Related Variables: Keep Your Friends Close
Block declarations are great for this.

```ms
fn main() {
  // Ah, database settings, all snug together.
  let (
    dbHost = "localhost"
    dbPort = 5432
    dbName = "myapp_production"
    dbUser = "super_admin" // (Hopefully not really)
  )
}
```

### Initialize Variables: Don't Leave Them Hanging
Give variables a starting value. It avoids confusion about their state.

```ms
fn main() {
  // Good: We know where we stand.
  let count = 0
  let totalAmount = 0.0
  let activeUsers = []
  
  // Less ideal: What are these right now? Null? Undefined? Spooky.
  let currentCount int
  let finalTotal float
  let userList []string
  // Manuscript might default them, but it's clearer to be explicit.
}
```

## Common Patterns: Tricks of the Trade

Some classic moves you'll see (and use).

### Swapping Variables: The Ol' Switcheroo
How to make `a` become `b` and `b` become `a`.

```ms
fn main() {
  let a = 10
  let b = 20
  print("Before swap: a = " + string(a) + ", b = " + string(b))
  
  // The classic temp variable shuffle
  let temp = a
  a = b
  b = temp
  
  print("After swap: a = " + string(a) + ", b = " + string(b))
  // Manuscript might offer more elegant ways to do this, like multi-assignment!
  // For example: a, b = b, a (if the language supports it)
}
```

### Default Values: Plan B for Variables
If you don't get a value from one source, have a backup.

```ms
fn main() {
  // Let's pretend getUserInput() might return null if the user is shy.
  let userInput = null // or "Bob" // getUserInput()
  let name = userInput != null ? userInput : "Anonymous"
  // This is a ternary operator: (condition ? value_if_true : value_if_false)
  
  print("Hello, " + name)
}
```

### Conditional Assignment: Choose Your Own Adventure (for a Variable)
Assign a value based on a condition.

```ms
fn main() {
  let score = 85
  let grade = score >= 90 ? "A" : score >= 80 ? "B" : score >= 70 ? "C" : score >= 60 ? "D" : "F"
  // Another ternary operator, this time chained. Readability can suffer if overdone.
  
  print("Your grade is: " + grade)
}
```

## Exercises: Time to Get Your Hands Dirty

Theory is nice, but practice is where the magic happens.

### Exercise 1: Digital You
Declare variables to store some basic info about yourself (or a fictional character).

```ms
fn main() {
  // Your mission, should you choose to accept it:
  let name = "Captain Coder"
  let age = 30 // Or your actual age, we don't judge
  let preferredLanguage = "Manuscript, obviously"
  let knowsKungFu = true // Or a more realistic skill
  
  // Now, print it all out in a fancy way!
  print("Behold! ${name}, aged ${age}, master of ${preferredLanguage}.")
  print("Does this hero know Kung Fu? ${knowsKungFu}!")
}
```

### Exercise 2: Simple Calculator
Flex those arithmetic muscles.

```ms
fn main() {
  let a = 20
  let b = 5 // Avoid zero for division, unless you like excitement
  
  let sum = a + b
  let difference = a - b
  let product = a * b
  let quotient = float(a) / float(b) // Use float for precise division
  let remainder = a % b             // The leftovers
  
  print("${a} + ${b} = ${sum}")
  print("${a} - ${b} = ${difference}")
  print("${a} * ${b} = ${product}")
  print("${a} / ${b} = ${quotient}")
  print("${a} % ${b} = ${remainder} (The Modulo Operator: your friend for cyclical tasks!)")
}
```

### Exercise 3: Destructuring Wizardry
Practice pulling values from arrays and objects like a pro.

```ms
fn main() {
  let starSystem = ["Sol", "Alpha Centauri", "Sirius"]
  let [localStar, nearestNeighbor, brightestStar] = starSystem
  
  let spaceship = {
    shipName: "MSS Enterprise"
    captain: "Jean-Luc Picard" // Or your name!
    topSpeed: "Warp 9.9"
  }
  let {shipName, captain} = spaceship
  
  print("Our local star is ${localStar}.")
  print("Nearest neighbor system: ${nearestNeighbor}.")
  print("The captain of the ${shipName} is ${captain}.")
}
```

## What's Next on Your Programming Odyssey?

You've wrestled with variables and types and emerged victorious! Now, prepare for:

1.  **[Learn about Functions](../functions/)** - Teach your code to perform reusable tricks.
2.  **[Master Control Flow](../control-flow/)** - Bend the program's execution to your will.
3.  **[Work with Collections](../data-structures/)** - Juggle lists and dictionaries of data.

{{% alert title="Don't Just Stare At It, Code It!" %}}
Knowing about variables is like knowing the ingredients for a cake. You only get to eat the cake (or, you know, run the program) if you actually mix them up and bake 'em. So, go forth and experiment!
{{% /alert %}}
