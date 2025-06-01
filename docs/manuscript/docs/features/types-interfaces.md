---
title: "Types and Interfaces"
linkTitle: "Types & Interfaces"

description: >
  Custom types, interfaces, methods, and type system features in manuscript.
---

Welcome to the world of Types and Interfaces, the dynamic duo that brings structure and sanity to your Manuscript code! Think of types as the DNA of your data, and interfaces as the contracts that keep everyone playing nicely together.

## Custom Types

Defining a custom type is like designing your own action figure or doll. What properties should it have? `name string`, `superPower string?` (that question mark means it's optional, maybe they're still discovering their powers!).
### Basic Type Definition
```ms
type User {
  name string
  email string
  age int
  active bool // Our User blueprint!
}
```

Blueprints for your data,
Fields and types, all well-defined,
Objects come alive.

### Type Instantiation Syntax

Ah, the great comma debate! Manuscript is pretty chill about commas when you're making new things from your types:
- **Multi-line party:** If each field is on its own line, living large, commas are optional. Manuscript gets it, you're giving each field its moment.
- **Single-line squeeze:** If you're lining them all up on one line, then yes, please use commas to keep them from bumping into each other. It's just good manners!

```ms
// Multi-line party: commas are optional (and often omitted for cleanliness)
let user1 = User{
  name: "Alice" // Commas are shy in multi-line...
  email: "alice@example.com"
  age: 30
  active: true // ...they often hide!
}

// Single-line squeeze: commas are a must!
let user2 = User{name: "Bob", email: "bob@example.com", age: 25, active: false} // But on one line, they're a must!

// Mixed format: if multiple fields share a line, they need commas between them.
let user3 = User{
  name: "Charlie", email: "charlie@example.com" // These two need a comma
  age: 35                                       // This one is fine alone
  active: true
}
```

### Typed vs Untyped Literals

Sometimes Manuscript is a super-smart detective and can guess the type (that's an untyped literal - 'Look Ma, no type name!'). Other times, especially when things are a bit ambiguous or you're just starting out with an empty collection, you gotta give it a clear clue with a typed literal (`let user User = ...`). It's all about context!
manuscript supports both typed and untyped literal syntax for creating instances:

#### Typed Literals
Explicitly specify the type name when creating instances:

```ms
// Typed literal - type is explicitly specified
let user = User{
  name: "Alice"
  email: "alice@example.com"
  age: 30
}

// Typed literal with single-line syntax
let product = Product{name: "Laptop", price: 999.99}
```

#### Untyped Literals
Create instances without specifying the type name when the type can be inferred:

```ms
let a = { // Manuscript often knows what you mean!
  name: "Bob"
  email: "bob@example.com"
  age: 25
}

// Variable with explicit type annotation
let user  = User {
  name: "Charlie"
  email: "charlie@example.com"
  age: 35
}

// Array of typed elements
let users User[] = [
  {name: "Alice", email: "alice@example.com", age: 30},
  {
    name: "Bob"
    email: "bob@example.com"
    age: 25
  }
]
```

#### When to Use Each

- **Typed literals**: Use these when you want to be crystal clear, especially if Manuscript might get confused (like with an empty list `[]` - is it a list of numbers? Strings? Tiny llamas?). Also great for one-off structures where you don't need a formal `type` definition everywhere.
- **Untyped literals**: Go for these when the type is super obvious from how you're using it – like assigning to a variable that already has a type, or in function parameters where the type is declared. Manuscript appreciates you not stating the obvious.

### Optional Fields
`string?` - That little question mark is your best friend for fields that might not always have a value. It's like saying, 'This *might* be here, or it *might not*. No pressure.'
```ms
type Product {
  name string
  price float
  description string?  // optional field // Might have it, might not. No biggie.
  category string?     // optional field
}

// Multi-line: commas optional
let product = Product{
  name: "Laptop"
  price: 999.99
  // description and category are optional
}

// Single-line: commas required
let product2 = Product{name: "Mouse", price: 29.99}
```

## Type Extension
`extends` is Manuscript's way of saying 'takes after.' So, an `Employee` can `extend` a `Person` (getting all their person-y qualities) and then add its own job-specific stuff. It's like genetic inheritance, but for code!

### Extending Types
```ms
type Person {
  name string
  age int
}

type Employee extends Person { // Employee gets all of Person's cool stuff, plus its own!
  employeeId string
  department string
  salary float
}
```

### Multiple Extension
```ms
type Timestamps {
  createdAt string
  updatedAt string
}

type User extends Person, Timestamps {
  email string
  isActive bool
}
```

## Type Aliases
Type aliases are nicknames for your types. `type UserId = string` means you can now use `UserId` instead of `string` when you mean it. Makes your code read more like a story and less like a... well, just a bunch of strings.

### Simple Aliases
```ms
type UserId = string
type Score = int
type Coordinates = (float, float)
```

### Complex Aliases
```ms
type EventHandler = fn(Event) void
```

## Interfaces
Interfaces are like rulebooks or contracts. 'Any type that wants to be considered `Drawable`,' says the interface, 'must promise to have a `draw()` method and a `getArea()` method.' It's all about keeping promises!

### Interface Definition
```ms
interface Drawable { // The "Drawable" club rules:
  draw() void       // Must know how to draw.
  getArea() float   // Must be able to calculate its area.
  getPerimeter() float // And its perimeter too!
}

interface Serializable {
  serialize() string
  deserialize(data string) void!
}
```

### Interface with Parameters
```ms
interface Repository[T] {
  get(id string) T!
  save(item T) void!
  delete(id string) void!
  list() T[]!
}
```

## Methods
Methods are functions that belong to a type. It's like teaching your `Robot` type how to `dance()` or `makeCoffee()`. These are the actions your custom types can perform.

### Implementing Methods
```ms
type Rectangle {
  width float
  height float
}

methods Rectangle as this { // Teaching Rectangle some tricks
  draw() void {
    print("Drawing rectangle: " + string(this.width) + "x" + string(this.height))
  }
  
  getArea() float {
    return this.width * this.height
  }
  
  getPerimeter() float {
    return 2 * (this.width + this.height)
  }
}
```

### Multiple Interface Implementation
```ms
methods Rectangle as this {
  serialize() string {
    return "Rectangle{" + string(this.width) + "," + string(this.height) + "}"
  }
  
  deserialize(data string) void! {
    // parsing logic
  }
}
```

## Advanced Type Features

### Generic Types
`Container[T]` - The `T` is a placeholder, like a 'Your Name Here' sticker. It means this container can hold any type you decide later. Super flexible!
```ms
type Container[T] {
  value T
  metadata map[string]string
}

// Multi-line: commas optional
let stringContainer = Container[string]{ // This container holds strings!
  value: "hello"
  metadata: ["type": "text"]
}

// Single-line: commas required  
let intContainer = Container[int]{value: 42, metadata: ["type": "number"]}
```

### Union Types
```ms
type Status = "pending" | "completed" | "failed"
type Result = int | string | Error

fn processResult(result Result) {
  match result {
    int: print("Number: " + string(result))
    string: print("Text: " + result)
    Error: print("Error: " + result.message())
  }
}
```

### Nested Types
```ms
type Company {
  name string
  address Address
  employees Employee[]
}

type Address {
  street string
  city string
  zipCode string
  country string
}
```

## Type Validation

### Runtime Type Checking
```ms
fn processValue(value any) string {
  return match typeof(value) {
    "string": "Text: " + value
    "int": "Number: " + string(value)
    "User": "User: " + value.name
    default: "Unknown type"
  }
}
```

### Type Guards
```ms
fn isUser(value any) bool {
  return typeof(value) == "User"
}

fn processUser(value any) {
  if isUser(value) {
    let user = value as User
    print("Processing user: " + user.name)
  }
}
```

## Practical Examples

### Domain Models
```ms
type Order {
  id string
  customerId string
  items OrderItem[]
  total float
  status OrderStatus
  createdAt string
}

type OrderItem {
  productId string
  quantity int
  price float
}

type OrderStatus = "pending" | "processing" | "shipped" | "delivered" | "cancelled"
```

### Service Interfaces
```ms
interface PaymentProcessor {
  processPayment(amount float, method PaymentMethod) PaymentResult!
  refund(transactionId string, amount float) RefundResult!
  getTransactionStatus(id string) TransactionStatus!
}

interface NotificationService {
  sendEmail(to string, subject string, body string) void!
  sendSMS(to string, message string) void!
  sendPush(userId string, title string, body string) void!
}
```

### Repository Pattern
```ms
interface UserRepository {
  create(user User) User!
  getById(id string) User!
  getByEmail(email string) User!
  update(user User) User!
  delete(id string) void!
  list(offset int, limit int) User[]!
}

type DatabaseUserRepository {
  connection DatabaseConnection
}

methods DatabaseUserRepository as UserRepository {
  create(user User) User! {
    // implementation
  }
  
  getById(id string) User! {
    // implementation  
  }
  
  // ... other methods
}
```

## Best Practices

### Type Design
- Use descriptive names for types and fields
- Keep types focused and cohesive
- Use optional fields appropriately
- Consider type composition over inheritance

### Interface Design
- Define clear contracts with interfaces
- Keep interfaces small and focused
- Use generic interfaces for reusability
- Document interface behavior

### Method Implementation
- Implement all interface methods
- Use meaningful method names
- Handle errors appropriately in methods
- Keep method logic focused

### Type Organization
```ms
// types/domain.ms
export type User {
  id string
  name string
  email string
}

// interfaces/services.ms  
export interface UserService {
  create(user User) User!
  getById(id string) User!
}

// implementations/user_service.ms
import { User } from '../types/domain.ms'
import { UserService } from '../interfaces/services.ms'

type DatabaseUserService {
  repository UserRepository
}

methods DatabaseUserService as UserService {
  // implementation
}
``` 