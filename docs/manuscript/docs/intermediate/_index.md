---
title: "Intermediate Guide"
linkTitle: "Intermediate"
weight: 20
description: >
  Dive deeper into Manuscript's unique features and advanced programming concepts.
---

Welcome to the Intermediate Guide! This section covers advanced Manuscript features that will help you write more powerful and expressive code. These concepts build on the fundamentals and introduce Manuscript's unique capabilities.

## What You'll Master

By completing this section, you'll understand:

- **Advanced Functions** - Closures, higher-order functions, and function expressions
- **Error Handling** - Bang functions, try expressions, and robust error patterns
- **Type System** - Custom types, interfaces, and type composition
- **Collections** - Advanced array, map, and set operations
- **Pattern Matching** - Powerful data destructuring and matching

## Prerequisites

Before starting this guide, you should be comfortable with:

- ✅ Basic variable declarations and types
- ✅ Simple function definition and calling
- ✅ Basic control flow (if/else, loops)
- ✅ Working with arrays and objects

If you need to review these topics, check out the [Beginner Guide](../beginner/).

## Learning Path

Follow these guides in order for the best experience:

### 1. [Advanced Functions](advanced-functions/)
Master sophisticated function patterns and techniques.

```ms
// Function expressions
let multiply = fn(a int, b int) int {
  return a * b
}

// Higher-order functions
fn map(arr []int, transform fn(int) int) []int {
  let result = []int
  for item in arr {
    result.append(transform(item))
  }
  return result
}

// Default parameters
fn connect(host string, port int = 8080, timeout int = 30) {
  // Connection logic
}
```

### 2. [Error Handling](error-handling/)
Learn Manuscript's powerful error handling system.

```ms
// Bang functions
fn readConfig() Config! {
  let content = try readFile("config.json")
  let config = try parseJSON(content)
  return config
}

// Error propagation
fn processData() Result! {
  let data = try loadData()
  let processed = try transformData(data)
  let validated = try validateData(processed)
  return validated
}

// Graceful error handling
fn main() {
  let result = try processData() else {
    print("Processing failed: ${error}")
    return
  }
  print("Success: ${result}")
}
```

### 3. [Type System](type-system/)
Create robust applications with custom types and interfaces.

```ms
// Custom types
type User {
  id int
  name string
  email string
  preferences UserPreferences
}

// Type aliases
type UserID = int
type EmailAddress = string

// Interfaces
interface Serializable {
  toJSON() string!
  fromJSON(data string) Self!
}

// Type extension
type AdminUser extends User {
  permissions []string
  lastLogin time.Time
}
```

### 4. [Collections and Maps](collections/)
Master advanced collection operations and data structures.

```ms
// Advanced array operations
let numbers = [1, 2, 3, 4, 5]
let doubled = numbers.map(fn(x) { x * 2 })
let evens = numbers.filter(fn(x) { x % 2 == 0 })
let sum = numbers.reduce(fn(acc, x) { acc + x }, 0)

// Maps and sets
let userMap = [
  "alice": User{name: "Alice", age: 30}
  "bob": User{name: "Bob", age: 25}
]

let uniqueIds = <1, 2, 3, 4, 5>
uniqueIds.add(6)
uniqueIds.remove(2)
```

### 5. [Pattern Matching](pattern-matching/)
Use pattern matching for elegant data handling.

```ms
// Match expressions
fn processResult(result Result) {
  match result {
    Success(value): print("Got: ${value}")
    Error(msg): print("Error: ${msg}")
    Pending: print("Still processing...")
    default: print("Unknown state")
  }
}

// Advanced destructuring
let user = {
  name: "Alice"
  contact: {
    email: "alice@example.com"
    phone: "+1234567890"
  }
  preferences: {
    theme: "dark"
    notifications: true
  }
}

let {name, contact: {email}, preferences: {theme}} = user
```

## Advanced Concepts Preview

### String Interpolation
```ms
fn formatUser(user User) string {
  return "User ${user.name} (ID: ${user.id}) - ${user.email}"
}

// Multi-line strings with interpolation
let template = """
Welcome, ${user.name}!

Your account details:
- Email: ${user.email}
- Member since: ${user.createdAt.format("2006-01-02")}
- Status: ${user.active ? "Active" : "Inactive"}
"""
```

### Tagged Templates
```ms
// SQL-like templates
let query = sql"""
  SELECT name, email, created_at
  FROM users 
  WHERE active = ${true}
  AND created_at > ${cutoffDate}
  ORDER BY created_at DESC
  LIMIT ${limit}
"""

// HTML templates
let html = html"""
  <div class="user-card">
    <h3>${user.name}</h3>
    <p>Email: ${user.email}</p>
    <p>Status: ${user.active ? "Active" : "Inactive"}</p>
  </div>
"""
```

### Async Patterns (Preview)
```ms
// Future async support
async fn fetchUserData(id int) User! {
  let user = await db.findUser(id)
  let preferences = await api.getUserPreferences(id)
  
  user.preferences = preferences
  return user
}

async fn main() {
  let users = []User
  
  // Concurrent operations
  let userTasks = []Task
  for id in userIds {
    userTasks.append(fetchUserData(id))
  }
  
  let results = await Task.all(userTasks)
  print("Loaded ${len(results)} users")
}
```

## Code Organization Patterns

### Module Pattern
```ms
// user.ms
export type User {
  id int
  name string
  email string
}

export fn createUser(name string, email string) User {
  return User{
    id: generateID()
    name: name
    email: email
  }
}

// main.ms
import { User, createUser } from './user'

fn main() {
  let user = createUser("Alice", "alice@example.com")
  print("Created user: ${user.name}")
}
```

### Builder Pattern
```ms
type QueryBuilder {
  table string
  fields []string
  conditions []string
  orderBy string
  limit int
}

fn newQuery(table string) QueryBuilder {
  return QueryBuilder{
    table: table
    fields: []
    conditions: []
  }
}

fn (qb QueryBuilder) select(fields ...string) QueryBuilder {
  qb.fields = fields
  return qb
}

fn (qb QueryBuilder) where(condition string) QueryBuilder {
  qb.conditions.append(condition)
  return qb
}

fn (qb QueryBuilder) build() string {
  // Build SQL query string
  return "SELECT ${join(qb.fields, ", ")} FROM ${qb.table}..."
}

// Usage
let query = newQuery("users")
  .select("name", "email", "created_at")
  .where("active = true")
  .where("created_at > '2024-01-01'")
  .build()
```

## Common Patterns

### Option/Maybe Pattern
```ms
type Option[T] {
  value T
  hasValue bool
}

fn some[T](value T) Option[T] {
  return Option[T]{value: value, hasValue: true}
}

fn none[T]() Option[T] {
  return Option[T]{hasValue: false}
}

fn (opt Option[T]) isSome() bool {
  return opt.hasValue
}

fn (opt Option[T]) unwrap() T! {
  if !opt.hasValue {
    return error("Unwrapped None value")
  }
  return opt.value
}

// Usage
fn findUser(id int) Option[User] {
  let user = database.query("SELECT * FROM users WHERE id = ${id}")
  if user != null {
    return some(user)
  }
  return none[User]()
}
```

### Result Pattern
```ms
type Result[T, E] {
  value T
  error E
  isSuccess bool
}

fn ok[T, E](value T) Result[T, E] {
  return Result[T, E]{value: value, isSuccess: true}
}

fn err[T, E](error E) Result[T, E] {
  return Result[T, E]{error: error, isSuccess: false}
}

// Usage
fn divideResult(a float, b float) Result[float, string] {
  if b == 0.0 {
    return err[float, string]("Division by zero")
  }
  return ok[float, string](a / b)
}
```

## Best Practices

### Error Handling
- Use bang functions (`!`) for operations that can fail
- Provide meaningful error messages
- Handle errors at the appropriate level
- Use `try`/`else` for graceful fallbacks

### Type Design
- Keep types focused and cohesive
- Use composition over inheritance
- Make illegal states unrepresentable
- Prefer explicit over implicit

### Function Design
- Write pure functions when possible
- Use descriptive parameter names
- Keep functions small and focused
- Leverage default parameters for flexibility

### Code Organization
- Group related functionality in modules
- Use clear and consistent naming
- Document public APIs
- Separate concerns appropriately

## What's Next?

After mastering the intermediate concepts:

- **[Advanced Guide](../advanced/)** - Complex patterns and optimization
- **[Tutorials](../tutorials/)** - Build complete applications
- **[Best Practices](../best-practices/)** - Production-ready code patterns

## Getting Help

If you encounter challenges:

1. **Review examples** - Each concept includes working code
2. **Check reference docs** - [Language Reference](../reference/)
3. **Ask questions** - [GitHub Discussions](https://github.com/manuscript-co/manuscript/discussions)
4. **Join the community** - [Discord](https://discord.gg/manuscript)

{{% alert title="Level Up Your Skills" %}}
The intermediate concepts are where Manuscript really shines. Take your time to understand each pattern - they'll make your code more robust and expressive.
{{% /alert %}} 