---
title: "Modules"
linkTitle: "Modules"

description: >
  Module system, imports, exports, and code organization in manuscript.
---

manuscript provides a module system for organizing code across files and packages using import and export declarations.

## Basic Module Structure

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

## Import Patterns

### Named Imports
```ms
import { functionName, variableName } from 'module.ms'
import { add, subtract, PI } from 'math.ms'
```

### Aliased Imports
```ms
import { add as mathAdd, subtract as mathSub } from 'math.ms'
import { Logger as Log } from 'logging.ms'
```

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

### Re-exports
```ms
// utils.ms
export { add, subtract } from 'math.ms'
export { format, parse } from 'string.ms'
```

## External Dependencies

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
- Keep modules focused on a single responsibility
- Use clear, descriptive module names
- Group related functionality together
- Minimize dependencies between modules

### Export Strategy
- Export only what's needed publicly
- Use descriptive names for exports
- Consider backwards compatibility
- Document exported interfaces

### Import Organization
- Group imports by type (standard library, external, local)
- Use consistent import style across project
- Avoid circular dependencies
- Keep imports at the top of files

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