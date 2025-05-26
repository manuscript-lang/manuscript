---
title: "Types and Interfaces"
linkTitle: "Types & Interfaces"

description: >
  Custom types, interfaces, methods, and type system features in manuscript.
---

manuscript provides a rich type system with custom types, interfaces, and methods for building structured and extensible applications.

## Custom Types

### Basic Type Definition
```ms
type User {
  name string
  email string
  age int
  active bool
}
```

### Type Instantiation Syntax

manuscript supports flexible comma usage in type instantiation:

- **Multi-line format**: Commas are optional when each field is on a separate line
- **Single-line format**: Commas are required to separate fields

```ms
// Multi-line: no commas needed
let user1 = User{
  name: "Alice"
  email: "alice@example.com"
  age: 30
  active: true
}

// Single-line: commas required
let user2 = User{name: "Bob", email: "bob@example.com", age: 25, active: false}

// Mixed format: commas required when multiple fields on same line
let user3 = User{
  name: "Charlie", email: "charlie@example.com"
  age: 35
  active: true
}
```

### Typed vs Untyped Literals

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
let a = {
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

- **Typed literals**: For storing strucuted data quickly, needed only for a small part of the code
- **Untyped literals**: Use when type is clear from context (function parameters, variable annotations, etc.)

### Optional Fields
```ms
type Product {
  name string
  price float
  description string?  // optional field
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

### Extending Types
```ms
type Person {
  name string
  age int
}

type Employee extends Person {
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

### Interface Definition
```ms
interface Drawable {
  draw() void
  getArea() float
  getPerimeter() float
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

### Implementing Methods
```ms
type Rectangle {
  width float
  height float
}

methods Rectangle as this {
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
```ms
type Container[T] {
  value T
  metadata map[string]string
}

// Multi-line: commas optional
let stringContainer = Container[string]{
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