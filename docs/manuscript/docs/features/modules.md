---
title: "Modules"
linkTitle: "Modules"

description: >
  Module system, imports, exports, and code organization in manuscript.
---

Imagine your program is a bustling city. Modules are like well-organized neighborhoods! Each one has its own specialty (math, string utilities, user services), keeping things tidy and preventing your codebase from turning into a sprawling, chaotic megapolis.

## Basic Module Structure

Think of `export` as putting a 'For Sale' sign on the cool stuff in your module. 'Hey world, I've got this awesome `add` function and a very important `PI` variable, come and get it!'
### Exporting from a Module
```ms
// math.ms
export fn add(a int, b int) int {
  return a + b
}

export fn multiply(a int, b int) int {
  return a * b
}

export let PI = 3.14159
```

`import` is like going shopping. You browse other modules and say, 'I'll take that `add` function, that `PI`, and oh, that `multiply` looks useful too!'
### Importing Modules
```ms
// main.ms
import { add, multiply, PI } from 'math.ms'

fn main() {
  let sum = add(5, 3)
  let product = multiply(4, 7)
  let area = PI * 2.5 * 2.5
}
```

Code in tidy rooms,
Share your best, hide all the mess,
Clean house, happy code.

## Import Patterns

### Named Imports
```ms
import { functionName, variableName } from 'module.ms'
import { add, subtract, PI } from 'math.ms'
```

Sometimes, names clash, or you just want a shorter nickname. `import { Logger as Log }` is like saying, 'Okay, `Logger` is a bit formal, I'm just gonna call you `Log` from now on.' Cool?
### Aliased Imports
```ms
import { add as mathAdd, subtract as mathSub } from 'math.ms'
import { Logger as Log } from 'logging.ms'
```

`import math from 'math.ms'` is like grabbing the entire toolkit from the 'math' workshop. Now you can use `math.add()`, `math.PI`, etc. Everything neatly namespaced!
### Target Import
```ms
import math from 'math.ms'

fn main() {
  let result = math.add(5, 3)
}
```

## Export Patterns

### Individual Exports
```ms
export fn processData(data string) string {
  return data.trim().upper()
}

export let CONFIG = {
  apiUrl: "https://api.example.com",
  timeout: 5000
}
```

### Type Exports
```ms
export type User {
  name string
  email string
  age int
}

export interface Validator {
  validate(data any) bool
}
```

Re-exporting is like creating a curated gift basket. You pick the best items from other modules and offer them as a convenient package from your own module. 'Everything you need, right here!'
### Re-exports
```ms
// utils.ms
export { add, subtract } from 'math.ms'
export { format, parse } from 'string.ms'
```

## External Dependencies

`extern` is your passport to the wider world of code! When you need to use powerful libraries written in Go (since Manuscript transpiles to Go), `extern` lets you declare them and bring their magic into your Manuscript project.
Use `extern` for external packages:

```ms
extern http from 'net/http'
extern json from 'encoding/json'

fn makeRequest(url string) string! {
  let response = try http.get(url)
  return response.body
}
```

## Module Organization

Just like a well-organized house has different rooms for different activities, a good Manuscript project has a clear file structure. `models` for your data blueprints, `services` for the brains of the operation, `utils` for those handy little tools.
### File Structure
```
project/
├── main.ms
├── models/
│   ├── user.ms
│   └── product.ms
├── services/
│   ├── auth.ms
│   └── api.ms
└── utils/
    ├── string.ms
    └── math.ms
```

### Models Module
```ms
// models/user.ms
export type User {
  id int
  name string
  email string
  createdAt string
}

export fn createUser(name string, email string) User {
  return User{
    id: generateId(),
    name: name,
    email: email,
    createdAt: now()
  }
}
```

### Services Module
```ms
// services/auth.ms
import { User } from '../models/user.ms'

export fn authenticate(email string, password string) User! {
  // authentication logic
}

export fn authorize(user User, permission string) bool {
  // authorization logic
}
```

## Best Practices

### Module Design
- Keep your modules focused, like a specialist shop. One for hats, one for shoes. Not a 'everything-must-go' jumble sale.
- Use clear, descriptive module names (e.g., `imageProcessor.ms` is better than `stuff.ms`).
- Group related functionality together – keep your socks in the sock drawer.
- Minimize dependencies between modules – you don't want a change in the 'kitchen' module to break the 'bathroom' module.

### Export Strategy
- Don't be an oversharer! Only `export` what other parts of your city actually *need* to see. Keep the internal plumbing hidden.
- Use descriptive names for exports – make it obvious what they do.
- Consider backwards compatibility when changing exported APIs – don't suddenly rename all the streets in your neighborhood!
- Document exported interfaces – a little note explaining what it's for goes a long way.

### Import Organization
- Group imports by type (standard library, external, local) – it's like organizing your pantry.
- Use consistent import style across project – pick a style and stick with it.
- Avoid creating tangled webs of imports that look like a spider had too much coffee. Circular dependencies are a no-no; it's like trying to mail a letter to yourself to deliver it.
- Keep imports at the top of files – no one likes finding a rogue sock in the cutlery drawer.

## Example: Complete Module System

### Data Types
```ms
// types/models.ms
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

### Business Logic
```ms
// services/user_service.ms
import { User } from '../types/models.ms'
import { validateEmail } from '../utils/validation.ms'

export fn createUser(name string, email string) User! {
  check validateEmail(email)
  check name != ""
  
  return User{
    id: generateId(),
    name: name,
    email: email
  }
}
```

### Utilities
```ms
// utils/validation.ms
export fn validateEmail(email string) bool {
  return email.contains("@") && email.contains(".")
}

export fn validateAge(age int) bool {
  return age >= 0 && age <= 150
}
```

### Main Application
```ms
// main.ms
import { createUser } from 'services/user_service.ms'
import { validateEmail } from 'utils/validation.ms'

fn main() {
  let user = try createUser("Alice", "alice@example.com")
  print("Created user: " + user.name)
}
``` 