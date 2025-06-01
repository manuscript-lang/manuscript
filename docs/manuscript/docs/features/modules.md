---
title: "Modules: Keeping Your Code's Workshop Tidy"
linkTitle: "Modules"

description: >
  Delving into Manuscript's module system: imports, exports, and the art of not tripping over your own code.
---

Ah, modules! If your codebase were a sprawling wizard's workshop, modules would be the neatly labeled chests, drawers, and shelves that keep your spell ingredients (functions, types, variables) organized and prevent catastrophic potion mix-ups. Manuscript provides a dandy module system for organizing code across different files and even packages, using the ancient arts of `import` and `export`.

## Basic Module Structure: Your First Bookshelf

Let's start with how to share your creations and borrow from others.

### Exporting from a Module: Sharing Your Magical Wares
To make functions, variables, or types available outside the current file (module), you must `export` them. It's like putting a "For Public Use" sign on your favorite inventions.

```ms
// Imagine this file is named math_spells.ms

// Exporting a function to perform addition.
export fn add(a int, b int) int {
  return a + b // The 'return' is optional here, but good for clarity.
}

// Exporting a multiplication function.
export fn multiply(a int, b int) int {
  return a * b
}

// Exporting a constant value (the sacred number PI, approximately).
export let PI = 3.14159
```

### Importing Modules: Borrowing Spells from Other Tomes
Now, in another file, you can `import` the goodies you've exported from `math_spells.ms`.

```ms
// Imagine this is main_program.ms
// We're importing specific items from our 'math_spells.ms' module.
import { add, multiply, PI } from 'math_spells.ms'

fn main() {
  let sum = add(5, 3)                 // Uses the imported 'add' function
  let product = multiply(4, 7)        // Uses the imported 'multiply'
  let circleArea = PI * 2.5 * 2.5     // Uses the imported 'PI'

  print("Sum: " + string(sum) + ", Product: " + string(product) + ", Area: " + string(circleArea))
}
```

## Import Patterns: Different Ways to Stock Your Shelves

Manuscript offers a few styles for importing, catering to your organizational preferences.

### Named Imports: Cherry-Picking Your Tools
This is what we saw above – you specify exactly which items you want by name.

```ms
// Grabbing specific functions and variables from 'module.ms'
import { functionName, variableName } from 'module.ms'

// A more concrete example from our math emporium
import { add, subtract, PI } from 'math_spells.ms' // Assuming subtract is also exported
```

### Aliased Imports: Giving Things Your Own Nicknames
Sometimes a name from an imported module might clash with something you already have, or you just prefer a shorter name. Use `as` to alias it.

```ms
// 'add' from math_spells.ms will be known as 'mathAdd' in this file.
import { add as mathAdd, subtract as mathSub } from 'math_spells.ms'
// 'Logger' from logging.ms will be known as 'Log'.
import { Logger as Log } from 'logging_services.ms'

// mathAdd(1,2)
// Log.info("...")
```

### Target Import (Namespace Import): Grabbing the Whole Shebang
Import everything exported from a module under a single namespace (like an object).

```ms
// Import everything from 'math_spells.ms' and put it under the 'math' namespace.
import math from 'math_spells.ms'

fn main_target_import() {
  let result = math.add(10, 5) // Call 'add' via the 'math' namespace.
  let circumference = 2 * math.PI * 5.0
  print("Math result: " + string(result) + ", Circumference: " + string(circumference))
}
```
> Code finds its own room,
> Clean shelves, no more tangled mess,
> Clarity takes hold.

## Export Patterns: How to Offer Your Wares

Just as there are different ways to import, there are flexible ways to export.

### Individual Exports: One by One
This is the most common way: put `export` in front of each function, variable, or type definition you want to make public.

```ms
// Exporting a data processing function.
export fn processData(data string) string {
  return data.trim().upper() // Example: trim whitespace and uppercase.
}

// Exporting a configuration object.
export let CONFIG = {
  apiUrl: "https://api.example.com/v1",
  timeout: 5000 // milliseconds
}
```

### Type Exports: Sharing Your Blueprints
You can export your custom type definitions too!

```ms
// Exporting a User type definition.
export type User {
  name string
  email string
  age int
  isAdmin bool
}

// Exporting an interface (a contract for what other types can do).
export interface Validator {
  validate(data any) bool! // This validator function itself can error!
}
```

### Re-exports: The Art of Delegation
Sometimes, a module might gather exports from other modules and re-export them, acting as a convenient central hub.

```ms
// Imagine this is master_utilities.ms

// Re-exporting 'add' and 'subtract' from 'math_spells.ms'.
export { add, subtract } from 'math_spells.ms'
// Re-exporting 'format' and 'parse' from 'string_tools.ms'.
export { format, parse } from 'string_tools.ms'

// Now, another file can import { add, format } from 'master_utilities.ms'
```

## External Dependencies: Importing from Distant Lands (Packages)

For code that isn't part of your immediate project (e.g., standard library modules or third-party packages), Manuscript uses `extern` to declare these dependencies. The exact mechanism for resolving these external packages would depend on Manuscript's build tools and package management system.

```ms
// Declaring that we intend to use 'http' features from an external 'net/http' package.
extern http from 'net/http'
// And 'json' features from an 'encoding/json' package.
extern json from 'encoding/json'

fn makeRequest(url string) string! { // This function might error!
  // Assuming http.get is how you use the imported external package.
  let response = try http.get(url)
  return response.body // Or however the response body is accessed.
}
```

## Module Organization: Structuring Your Grand Library

How you arrange your files and directories matters for maintainability.

### File Structure: A Suggested Layout
A common way to organize a project:

```
my_awesome_project/
├── main.ms                 // Your program's grand entrance
├── models/                 // For your data blueprints (custom types)
│   ├── user.ms
│   └── product.ms
├── services/               // For business logic, API interactions, etc.
│   ├── authentication_service.ms
│   └── data_processing_service.ms
└── utils/                  // For helper functions, shared tools
    ├── string_helpers.ms
    └── math_wonders.ms
```

### Models Module Example: Defining Your Data Entities
What a `user.ms` file inside `models/` might look like:

```ms
// In file: models/user.ms

// Assume generateId() and now() are utility functions defined elsewhere or globally.
// fn generateId() int { /* ... */ }
// fn now() string { /* ... */ }


export type User {
  id int
  name string
  email string
  createdAt string // When the user account was conjured.
}

export fn createUser(name string, email string) User {
  return User{
    id: 123, // Replace with actual ID generation: generateId(),
    name: name,
    email: email,
    createdAt: "2024-03-10" // Replace with actual timestamp: now()
  }
}
```

### Services Module Example: Implementing Core Logic
What `authentication_service.ms` inside `services/` might contain:

```ms
// In file: services/authentication_service.ms

// Importing the User type from our models directory.
// The '../' means "go up one directory level."
import { User } from '../models/user.ms'

export fn authenticate(email string, password string) User! { // Might error!
  // ... sophisticated authentication logic here ...
  // For example, find user by email, check password hash.
  if email == "test@example.com" && password == "password123" {
    return User{id: 1, name: "Test User", email: email, createdAt: "..."}
  }
  error("Authentication failed: Invalid credentials, perhaps a typo in the magic word?")
}

export fn authorize(user User, permission string) bool {
  // ... authorization logic: does this user have the right permission? ...
  // For example, check user.roles or user.permissions.
  if user.name == "Test User" && permission == "access_secret_chamber" {
    return true
  }
  return false
}
```

## Librarian's Lore: Best Practices for Modules

Some sage advice for keeping your module system from devolving into a chaotic mess.

### Module Design Philosophy
- **Keep Modules Focused:** Each module should have a clear purpose or manage a single responsibility (like a specific domain, e.g., "user authentication" or "string manipulation"). Don't make "kitchen sink" modules.
- **Clear Naming:** Use clear, descriptive names for your module files (e.g., `user_authentication.ms` is better than `stuff.ms`).
- **Group Related Functionality:** If several functions and types work closely together, they probably belong in the same module.
- **Minimize Dependencies:** Try to reduce how many other modules a given module needs to import. Loose coupling makes for a more flexible and maintainable workshop.

### Export Strategy: What to Share and How
- **Export Only What's Necessary:** If a function or variable is only used internally within the module, don't export it. Keep your public interface clean and minimal.
- **Descriptive Export Names:** Ensure your exported names are clear and unambiguous to users of your module.
- **Backwards Compatibility:** Think twice before removing or renaming exports from a widely used module, as it can break other wizards' spells.
- **Document Your Exports:** Especially for types and functions, good comments explaining what they are and how to use them are invaluable.

### Import Organization: Keeping Your Imports Tidy
- **Group Imports:** Consider grouping your imports: standard library first, then external packages, then your local project modules. This improves readability.
- **Consistent Style:** Pick an import style (e.g., always named imports, or always target imports for certain things) and stick to it within a project.
- **Avoid Circular Dependencies:** This is where module A imports module B, and module B imports module A. This can lead to headaches and is usually a sign that your modules need rethinking.
- **Imports at the Top:** It's conventional to place all your `import` (and `extern`) statements at the very beginning of the file.

## Example: A Miniature Module Ecosystem

Let's see a small, complete system to illustrate these ideas.

### Data Types Definition
```ms
// In file: types/models.ms

export type User {
  id int
  name string
  email string
}

export type Product {
  id int
  name string
  price float
  category string
}
```

### Business Logic Service
```ms
// In file: services/user_service.ms

import { User } from '../types/models.ms' // Go up one dir, then into types
import { validateEmail } from '../utils/validation.ms' // Go up, then into utils

// Assume generateId() is a global or imported utility
// fn generateId() int { return Math.randomInt(10000); }

export fn createUser(name string, email string) User! { // Can error
  check validateEmail(email) // from ../utils/validation.ms
  check name != ""           // Basic name check
  
  return User{
    id: 12345, // generateId(),
    name: name,
    email: email
  }
}
```

### Utility Functions
```ms
// In file: utils/validation.ms

export fn validateEmail(email string) bool { // Simple validation
  return email.contains("@") && email.contains(".")
}

export fn validateAge(age int) bool { // Another utility
  return age >= 0 && age <= 150 // World record is less than 130, so this is generous!
}
```

### Main Application Entry Point
```ms
// In file: main.ms (at the project root)

import { createUser } from 'services/user_service.ms' // Relative to project root or configured paths
// Assuming 'validateEmail' is not directly needed in main, but used by user_service.

fn main() {
  print("Attempting to create a new user...")
  let user = try createUser("Alice Wonderland", "alice@example.com") catch {
    print("User creation failed: ${error}")
    return // Exit if user creation fails
  }

  print("Successfully created user: " + user.name + " with email: " + user.email)
}
```
