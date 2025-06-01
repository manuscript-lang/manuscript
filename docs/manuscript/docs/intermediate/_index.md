---
title: "Intermediate Guide: Level Up Your Manuscript Wizardry!"
linkTitle: "Intermediate"

description: >
  Ready to dive deeper? Explore Manuscript's unique features, advanced programming spells, and become an even more formidable coder!
---

Welcome, brave coder, to the Intermediate Sanctum! You've mastered the basics, your "Hello, World!" echoes with confidence, and variables practically bow at your command. Now, it's time to delve into Manuscript's more sophisticated enchantments. This section will help you write code that's not just functional, but also powerful, expressive, and elegant. These concepts build upon your solid foundation and introduce some of Manuscript's most unique and potent capabilities. Prepare to be amazed (by your own growing skills)!

## What Arcane Knowledge You'll Master

By the time you emerge from this section, your grimoire will be significantly thicker, and you'll wield these powers with finesse:

- **Advanced Functions**: Unravel the mysteries of closures, higher-order functions, and the subtle art of function expressions. Functions within functions? Functions *as* data? Oh yes!
- **Error Handling Mastery**: Learn to command bang functions (!), deftly `try` risky operations, and develop robust error patterns that make your code resilient.
- **The Deeper Type System**: Forge your own custom types, define powerful contracts with interfaces, and compose types with elegance. Your data will be so well-structured, it'll sing.
- **Collections & Their Secrets**: Unlock advanced maneuvers for arrays, maps, and sets. Bend collections to your will!
- **Pattern Matching Prowess**: Wield the mighty `match` expression for incredibly clear and powerful data destructuring and conditional logic.

> Simple spells now known,
> Deeper magic starts to call,
> Power grows within.

## Your Pre-Flight Checklist (Prerequisites)

Before you soar into these intermediate skies, make sure you're comfortable piloting the basics:

- ✅ Declaring variables and understanding their types (your trusty wand and basic ingredients).
- ✅ Defining and calling simple functions (casting your first cantrips).
- ✅ Basic control flow with `if/else` and loops (directing simple enchantments).
- ✅ Working with arrays and objects (your initial potion ingredients and storage boxes).

If any of these feel a bit rusty, a quick visit to the [Beginner Guide](../beginner/) might be a good warm-up!

## Your Advanced Learning Path: Trials of a Journeyman Coder

Follow these scrolls in order for the most enlightening (and least bewildering) experience. Each step unveils new powers!

### 1. [Advanced Functions](advanced-functions/)
Time to go beyond simple function calls. Master sophisticated patterns and techniques that will make your code more flexible and powerful.

```ms
// Behold! Function expressions (assigning a function to a variable).
let multiply = fn(a int, b int) int { // This function has no name, but 'multiply' holds it.
  return a * b
}
// multiply(3, 4) // Result: 12

// Higher-order functions: Functions that operate on other functions!
// 'mapItems' takes an array and a 'transform' function as arguments.
fn mapItems(arr []int, transform fn(int) int) []int {
  let result = []int
  for item in arr {
    result.append(transform(item)) // Applies the 'transform' to each item.
  }
  return result
}
// mapItems([1,2,3], fn(x){ x * 2 }) // Result: [2,4,6]


// Default parameters: For when you want sensible defaults.
fn connect(host string, port int = 8080, timeout int = 30000) {
  print("Connecting to ${host}:${port} with timeout ${timeout}ms...")
  // ... actual connection logic ...
}
// connect("my-server.com") // Uses default port and timeout.
// connect("another-server.com", port: 9000) // Custom port.
```

### 2. [Error Handling](error-handling/)
Learn Manuscript's robust error handling system. Because sometimes, even the best spells fizzle.

```ms
// Bang functions (!): Signaling that a function might return an error.
fn readConfig() Config! { // This function promises a Config OR an error.
  let content = try readFile("config.json") // 'try' calls another bang function.
  let config = try parseJSON(content)     // And another!
  return config // Only if both 'try' calls succeed.
}

// Error propagation: Errors naturally bubble up the call stack.
fn processData() Result! { // This also can error.
  let data = try loadData()
  let processed = try transformData(data)
  let validated = try validateData(processed)
  return validated // The final result, or an error from any step.
}

// Graceful error handling with 'try...else'.
fn main_error_handling() {
  let result = try processData() else { // If processData errors...
    print("Oh dear, processing failed: ${error}") // 'error' holds the error details.
    return // Exit gracefully.
  }
  print("Success! Result: ${result}")
}
```

### 3. [Type System](type-system/)
Forge robust and maintainable applications by mastering custom types, interfaces, and the art of type composition.

```ms
// Custom types: Your own data blueprints!
type User {
  id int
  name string
  email string
  preferences UserPreferences // Types can contain other custom types!
}
// type UserPreferences { theme string, notifications bool } // Define this too!

// Type aliases: More readable names for existing types.
type UserID = int
type EmailAddress = string

// Interfaces: Defining contracts for what types can DO.
interface Serializable {
  toJSON() string! // Must have a toJSON method that might error.
  fromJSON(data string) Self! // And a fromJSON method. 'Self' refers to the implementing type.
}

// Type extension: Building new types based on existing ones.
type AdminUser extends User { // An AdminUser IS A User, plus more.
  permissions []string
  lastLogin time.Time // Assuming 'time.Time' is a defined type.
}
```

### 4. [Collections and Maps](collections/)
Become a virtuoso with advanced collection operations and sophisticated data structures.

```ms
// Advanced array operations: map, filter, reduce!
let numbers = [1, 2, 3, 4, 5, 6]
let doubled = numbers.map(fn(x) { x * 2 })       // [2, 4, 6, 8, 10, 12]
let evens = numbers.filter(fn(x) { x % 2 == 0 })  // [2, 4, 6]
let sum = numbers.reduce(fn(acc, x) { acc + x }, 0) // 21 (0 is initial acc)

// Maps (dictionaries) and Sets (unique collections).
// type User { name string, age int } // Assuming User is defined.
let userMap = [ // A map where keys are strings, values are User objects.
  "alice123": User{name: "Alice", age: 30},
  "bob_the_coder": User{name: "Bob", age: 25}
]

let uniqueIds = <101, 102, 103, 104, 105> // A set of unique IDs.
uniqueIds.add(106)    // Adds 106.
uniqueIds.add(101)    // Tries to add 101 again, but sets only keep unique values!
uniqueIds.remove(102) // Removes 102.
// print(userMap["alice123"].name) // Alice
// print(uniqueIds.contains(101)) // true
```

### 5. [Pattern Matching](pattern-matching/)
Wield the power of `match` expressions for elegant and powerful ways to handle data based on its shape and value.

```ms
// type Result { value any, error string } // A conceptual Result type
// type Success extends Result { value any }
// type Error extends Result { message string }
// type State = "Pending" | "Complete" | "Failed" // A union type

// Match expressions: Like a super-powered switch statement.
fn processMyResult(myResult Result) { // Assuming Result is a custom type or interface
  match myResult {
    Success(value): print("Hooray! Got value: ${value}") // Destructures Success
    Error(msg): print("Bummer. Error encountered: ${msg}") // Destructures Error
    // Pending: print("Still waiting for it to finish...") // If Result could be a simple string state
    default: print("Unknown result state. How curious!")
  }
}

// Advanced destructuring within a match or even with 'let'.
let user = {
  name: "Alice",
  contact: {
    email: "alice@example.com",
    phone: "+1234567890"
  },
  preferences: {
    theme: "dark",
    notifications: true,
    language: "en"
  }
}

// Destructure deeply nested fields into variables!
let {name, contact: {email}, preferences: {theme, language}} = user
// Now you have 'name', 'email', 'theme', and 'language' as local variables.
// print("${name}'s email is ${email}, preferred theme is ${theme} in ${language}.")
```

## Sneak Peek: Even More Advanced Sorcery (Concepts Preview)

Just to whet your appetite, here are a few more advanced topics you might encounter later or that are emerging in Manuscript:

### String Interpolation (You've Seen It, But It's Powerful!)
Effortlessly embed expressions within strings.
```ms
// Assuming user is an object with name, id, email, createdAt, active fields.
// And createdAt has a format method.
fn formatUserForDisplay(user User) string {
  return "User ${user.name} (ID: ${user.id}) - Email: ${user.email}"
}

// Multi-line strings with interpolation are great for templates.
let emailTemplate = """
Subject: Welcome to the Manuscript Guild, ${user.name}!

Hello ${user.name},

We're thrilled to have you. Your account details:
- Email: ${user.email}
- Member since: ${user.createdAt.format("YYYY-MM-DD")}
  (conceptual date formatting)
- Status: ${user.active ? "Shining Brightly (Active)" : "Currently Snoozing (Inactive)"}
"""
```

### Tagged Templates: Functions That Process Your Strings
A powerful feature where a function processes a template literal. Often used for things like HTML generation or SQL query building, ensuring safety and proper formatting.

```ms
// Conceptual: SQL-like templates for safer queries.
// let query = sql"""
//   SELECT name, email, created_at
//   FROM users
//   WHERE active = ${true}
//   AND created_at > ${cutoffDateVariable} // Variables are safely handled
//   ORDER BY created_at DESC
//   LIMIT ${limitVariable}
// """

// Conceptual: HTML templates for building UI components.
// let userCardHtml = html"""
//   <div class="user-profile-card">
//     <h3>${user.name}</h3>
//     <p>Contact: ${user.email}</p>
//     <p>Account Status: ${user.active ? "Ready for Action" : "Taking a Nap"}</p>
//   </div>
// """
```

### Async Patterns (A Glimpse into the Future of Concurrency)
Manuscript is designed with modern programming needs in mind, including asynchronous operations. (Syntax and features here are illustrative of common async patterns).

```ms
// Conceptual: How async/await might look in Manuscript for non-blocking operations.
async fn fetchUserDataFromServer(id int) User! { // An async function that might error
  let userJson = await httpClient.get("/users/${id}") // 'await' pauses until the data arrives
  let preferencesJson = await httpClient.get("/users/${id}/preferences")
  
  let user = try User.fromJSON(userJson) // Assuming fromJSON can error
  user.preferences = try Preferences.fromJSON(preferencesJson) // Add preferences
  return user
}

async fn main_async_example() {
  print("Fetching multiple users concurrently...")
  let userIds = [1, 2, 3, 4, 5]
  let userTasks = [] // A list to hold our asynchronous tasks/promises
  
  for id in userIds {
    userTasks.append(fetchUserDataFromServer(id)) // Start each task
  }
  
  // 'Task.all' would wait for all tasks to complete.
  // Results might be an array of Users or an array of Results (value/error).
  let results = await Task.all(userTasks)
  print("Finished loading ${len(results)} users (some might have failed).")
}
```

## Organizing Your Spellbook: Code Organization Patterns

As your projects grow, how you structure your code becomes crucial.

### The Trusty Module Pattern
You've met modules! They are Manuscript's primary way to keep code organized in separate files and namespaces.

```ms
// In a file named user_module.ms:
export type User { /* ... fields ... */ }
export fn createUser(name string, email string) User { /* ... logic ... */ }

// In your main.ms or another module:
import { User, createUser } from './user_module.ms' // Assuming relative path

fn main_module_pattern() {
  let newUser = createUser("Gandalf", "gandalf@middleearth.com")
  print("New user conjured: ${newUser.name}")
}
```

### The Builder Pattern: Crafting Complex Objects Step-by-Step
For objects that require complex setup, the Builder pattern provides a clear, step-by-step construction process.

```ms
// Conceptual Builder for a 'Query' object
type QueryBuilder {
  table string
  fields []string
  conditions []string
  orderBy string
  limit int
}

fn newQuery(table string) QueryBuilder { /* ... initializes QueryBuilder ... */ }
fn (qb QueryBuilder) select(fields ...string) QueryBuilder { /* ... adds fields ... */ }
fn (qb QueryBuilder) where(condition string) QueryBuilder { /* ... adds condition ... */ }
// ... other builder methods like orderBy, limit ...
fn (qb QueryBuilder) build() string { /* ... constructs the final query string ... */ }

// Usage: A fluent way to build a query.
let myQueryString = newQuery("characters")
  .select("name", "class", "level")
  .where("race = 'Elf'")
  .where("level > 10")
  // .orderBy("level DESC")
  .build()
// print(myQueryString)
```

## Advanced Alchemical Concoctions: Common Patterns

Some powerful patterns emerge when you combine Manuscript's features.

### Option/Maybe Pattern: Handling "Maybe It's There, Maybe It's Not"
For values that might be absent, instead of using `null` directly and risking errors, the Option (or Maybe) pattern provides a type-safe way to represent optionality.

```ms
// Conceptual Option type
type Option[T] { // 'T' is a generic type parameter
  value T
  hasValue bool
}

fn some[T](value T) Option[T] { /* returns Option with hasValue=true */ }
fn none[T]() Option[T] { /* returns Option with hasValue=false */ }

fn (opt Option[T]) isSome() bool { return opt.hasValue }
fn (opt Option[T]) unwrap() T! { /* returns value if isSome, else errors */ }

// Usage:
fn findUserByID(id int) Option[User] { // Returns an Option that might contain a User
  // let user = database.query("SELECT * FROM users WHERE id = ${id}") // Hypothetical DB call
  // if user != null {
  //   return some(user) // We found a user!
  // }
  return none[User]() // No user found for this ID.
}

// let userOption = findUserByID(123)
// if userOption.isSome() {
//   let actualUser = try userOption.unwrap() // Safely get the user
//   print("Found user: ${actualUser.name}")
// } else {
//   print("User 123 not found in our records.")
// }
```

### Result Pattern: For Outcomes That Can Be Success OR Failure
Similar to Option, but explicitly for operations that can succeed (with a value) or fail (with an error). Manuscript's built-in error handling with `!` and `try/else` often covers this, but you might define custom Result types for more complex scenarios.

```ms
// Conceptual Result type
type Result[TValue, TError] { // Generic for success value type and error type
  value TValue
  error TError
  isSuccess bool
}

fn ok[TV, TE](value TV) Result[TV, TE] { /* returns Result with isSuccess=true */ }
fn err[TV, TE](errorValue TE) Result[TV, TE] { /* returns Result with isSuccess=false */ }

// Usage:
fn performRiskyOperation(input int) Result[string, string] { // Returns string on success, string error message on failure
  if input < 0 {
    return err[string, string]("Input cannot be negative for this delicate operation.")
  }
  if input == 0 {
    return err[string, string]("Input zero causes a paradox here!")
  }
  return ok[string, string]("Operation successful! Result: ${input * 100}")
}

// let outcome = performRiskyOperation(0)
// if outcome.isSuccess {
//   print(outcome.value)
// } else {
//   print("Failed: " + outcome.error)
// }
```

## Sage Advice: Best Practices for Intermediate Sorcery

As your powers grow, so does the need for wisdom and discipline!

### Error Handling Etiquette
- Embrace bang functions (`!`) for any operation that isn't guaranteed to succeed. It's honest and helpful.
- Write error messages that are actually useful. "Error occurred" helps no one. "Failed to connect to database at 'db.example.com': Timeout" is much better.
- Handle errors where it makes sense. Sometimes that's immediately with `try/else`; sometimes it's letting them propagate to a higher-level handler.
- `try/else` is your friend for providing graceful fallbacks or alternative paths.

### Type Design Craftsmanship
- Keep your custom types focused on a single, clear concept. Don't create "God objects" that know and do everything.
- Composition (having types contain other types) is often more flexible and easier to reason about than very deep inheritance hierarchies.
- Strive to make illegal states unrepresentable with your types. If a `PublishedArticle` must have a `publishDate`, make it a non-optional field.
- Be explicit with your types when it adds clarity, but let Manuscript infer when the context is obvious.

### Function Design Finesse
- Aim for pure functions (output depends only on input, no side effects) when possible. They are easier to test and reason about.
- Use clear, descriptive names for your parameters. `fn process(d any)` is less clear than `fn processUser(user User)`.
- Keep functions relatively small and focused on doing one thing well. If a function gets too long, it's probably trying to do too much.
- Default parameters can make functions more convenient to call for common use cases.

### Code Organization Wisdom
- Group related functionality into modules. This keeps your codebase tidy and easier to navigate.
- Use clear and consistent naming conventions for files, types, functions, and variables.
- Document your public APIs (exported functions, types, interfaces) so others (and your future self) know how to use them.
- Think about separation of concerns: UI logic, business logic, and data access logic often benefit from being in different parts of your codebase.

## What's Next on Your Path to Enlightenment?

You've waded into the deeper waters of Manuscript and emerged wiser! What quests await?

- **[Advanced Guide](../advanced/)**: For those who wish to explore the most complex patterns, performance optimization techniques, and the very frontiers of Manuscript mastery.
- **[Tutorials](../tutorials/)**: Put your intermediate skills to the test by building complete applications and tackling real-world problems.
- **[Best Practices Guide](../best-practices/)**: Learn more about writing production-ready, robust, and maintainable Manuscript code.

## When You Need a Guiding Star (Getting Help)

Even seasoned adventurers sometimes consult the oracle. If you find yourself stuck or pondering a particularly tricky enchantment:

1.  **Revisit the Examples**: Each concept in these guides usually comes with working code. Double-check them!
2.  **Consult the Ancient Scrolls**: The [Language Reference](../reference/) has the definitive word on syntax and semantics.
3.  **Seek Wisdom from the Council**: Ask questions on [GitHub Discussions](https://github.com/manuscript-lang/manuscript/discussions) (or other community forums as they arise).
4.  **Join the Guild**: Connect with fellow Manuscript practitioners on [Discord](https://discord.gg/manuscript) (if available/applicable) or other community channels.

{{% alert title="You're Leveling Up Your Skills!" %}}
These intermediate concepts are where Manuscript truly begins to flex its muscles. Take your time, experiment with each pattern, and don't be afraid to break things (that's how you learn!). The power you're gaining will make your code more robust, expressive, and frankly, more awesome.
{{% /alert %}}
