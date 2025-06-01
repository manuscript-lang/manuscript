---
title: "Types & Interfaces: Crafting Your Code's Blueprints"
linkTitle: "Types & Interfaces"

description: >
  Designing custom types, defining contracts with interfaces, implementing methods, and wielding Manuscript's powerful type system like a master architect.
---

Welcome, esteemed Code Architects and Digital Designers! Manuscript boasts a rich and flexible type system, allowing you to go beyond basic primitives and construct your own custom data blueprints (types) and define clear contracts for how they should behave (interfaces). This is where you truly start building structured, robust, and surprisingly extensible applications. Let's lay the foundation!

## Custom Types: Your Personalized Data Containers

Tired of generic boxes? With custom types, you can design bespoke containers perfectly tailored to hold specific kinds of information.

### Basic Type Definition: Sketching Your First Blueprint
Use the `type` keyword to declare your new data structure. Think of it as drafting the initial design for your custom container.

```ms
// Blueprint for a 'User' data container
type User {
  name string       // A field for the user's name (text)
  email string      // Their electronic mail address (also text)
  age int           // How many trips around the sun (a whole number)
  active bool       // Are they currently active? (true or false)
}
```

### Type Instantiation Syntax: Bringing Your Blueprints to Life!

Once you have a blueprint (type), you need to construct an actual instance of it. Manuscript is pretty chill about commas when you're building these instances.

- **Multi-line format**: If each field is on its own line, commas are mostly just for show (optional).
- **Single-line format**: If you're cramming fields onto one line, commas are your best friends for telling them apart (required).

```ms
// Multi-line: Commas are taking a vacation.
let user1 = User{
  name: "Alice"
  email: "alice@example.com"
  age: 30
  active: true
}

// Single-line: Commas are on duty, keeping things orderly.
let user2 = User{name: "Bob", email: "bob@example.com", age: 25, active: false}

// Mixed format: If multiple fields share a line, the comma police will be there.
let user3 = User{
  name: "Charlie", email: "charlie@example.com" // Comma needed here!
  age: 35                                      // No comma needed before 'age' if on new line
  active: true
}
```

### Typed vs Untyped Literals: To Name or Not to Name (Your Instance's Type)

Manuscript offers flexibility when you're creating instances.

#### Typed Literals: "I Declare This to Be a User!"
You explicitly state the type's name when creating the instance. No ambiguity here!

```ms
// Clearly stating this is a 'User' instance.
let user = User{ // User{} is the typed literal
  name: "Alice"
  email: "alice@example.com"
  age: 30
}

// Another example, perhaps for a 'Product' type.
// type Product { name string, price float }
// let laptop = Product{name: "Laptop Xtreme", price: 999.99}
```

#### Untyped Literals: "You Know What I Mean, Manuscript..."
Sometimes, the context is so clear that Manuscript can infer the type you're creating, even if you don't explicitly name it. This is often used when assigning to an already typed variable or in array/map initializations where the type is known.

```ms
// 'a' is initially an untyped object/map-like structure.
// Its precise type might be inferred later or it might remain a generic object.
let a = {
  name: "Bob the Untyped"
  email: "bob@example.com"
  age: 25
}

// Here, 'user' is explicitly annotated as User, so the literal on the right
// doesn't need to repeat 'User'. Manuscript gets the hint.
let user User = { // The {} part is an untyped literal, context provides 'User'
  name: "Charlie the Clearly Typed"
  email: "charlie@example.com"
  age: 35
}

// For an array where elements are known to be Users:
// type User { name string, email string, age int }
let users User[] = [ // Array type is User[]
  {name: "Alice", email: "alice@example.com", age: 30}, // Untyped literal, becomes User
  { // Another untyped literal, also becomes User
    name: "Bob"
    email: "bob@example.com"
    age: 25
  }
]
```

#### When to Wield Which Wand
- **Typed Literals (`User{...}`):** Great for one-off structures or when you want to be absolutely explicit at the point of creation, especially if the variable isn't already typed. Useful for quickly creating structured data that might only be used locally.
- **Untyped Literals (`{...}`):** Super handy when the type is obvious from the context, like assigning to a variable that already has a type declaration (`let user User = {...}`), passing as a function argument where the parameter is typed, or initializing typed collections. Reduces verbosity.

### Optional Fields: "Is It There? Maybe, Maybe Not!"
Sometimes, a piece of information isn't mandatory. Mark fields as optional with a `?` after their type.

```ms
type Product {
  name string
  price float
  description string?  // The '?' whispers, "This might be null or absent."
  category string?     // So might this.
}

// Multi-line: still no comma fuss for optional fields if on new lines.
let fancyLaptop = Product{
  name: "Laptop Pro Max Ultra"
  price: 1999.99
  // 'description' and 'category' are happily omitted. They'll be null or some equivalent.
}

// Single-line: commas are still the law for multiple fields on one line.
let basicMouse = Product{name: "Simple Mouse", price: 19.99, category: "Peripherals"}
// 'description' is omitted here.
```

## Type Extension: Standing on the Shoulders of Giants (or Other Types)

Why reinvent the wheel when you can inherit features from an existing type?

### Extending Types: Building Upon Existing Blueprints
Create a new type that includes all the fields of an existing type, plus some new ones.

```ms
type Person { // Our basic human blueprint
  name string
  age int
}

// An 'Employee' is a 'Person' with a job.
type Employee extends Person { // Inherits 'name' and 'age' from Person
  employeeId string
  department string
  salary float      // Ka-ching!
}

// let emp = Employee{name: "Dave", age: 40, employeeId: "E123", department: "Magic", salary: 70000}
```

### Multiple Extension: The "Voltron" of Types!
A type can inherit from multiple other types, combining all their fields. (Use with caution; can lead to complex structures if overdone!)

```ms
type Timestamps { // A handy blueprint for tracking creation/update times
  createdAt string
  updatedAt string
}

// Our User is a Person, and also has Timestamps. What a multifaceted individual!
type User extends Person, Timestamps {
  email string
  isActive bool
}

// let superUser = User{name:"Super Alice", age:30, createdAt:"yesterday", updatedAt:"today", email:"super@example.com", isActive:true}
```
> Shape takes solid form,
> Data knows its name and place,
> Order reigns supreme.

## Type Aliases: Giving New Names to Old Friends (or Complex Acquaintances)

Sometimes a type signature is long or you want to give a more domain-specific name to an existing type. Aliases to the rescue!

### Simple Aliases: Quick Nicknames
For primitive types or simple structures.

```ms
type UserId = string          // A 'UserId' is just a fancy name for a 'string'.
type Score = int              // 'Score' is a more descriptive term for an 'int' in some contexts.
type Coordinates = (float, float) // 'Coordinates' is a tuple of two floats. More readable!
```

### Complex Aliases: Nicknames for Complex Spell Signatures
Especially useful for function types.

```ms
// 'EventHandler' is an alias for a function that takes an 'Event' type (assume Event is defined)
// and returns nothing (void).
type EventHandler = fn(Event) void
// Now you can declare variables like: let myHandler EventHandler = someFunction
```

## Interfaces: Defining Contracts and Promises

Interfaces define a "contract" or a "shape" that different types can adhere to. They specify *what* methods a type must have, but not *how* those methods are implemented. It's all about capabilities!

### Interface Definition: Laying Down the Law
What methods must a type implement to be considered, say, `Drawable` or `Serializable`?

```ms
// Anything that wants to be 'Drawable' must promise to have these three methods.
interface Drawable {
  draw() void         // A method to draw itself.
  getArea() float     // A method to calculate its area.
  getPerimeter() float // And its perimeter.
}

// Anything 'Serializable' must know how to turn itself into text and back.
interface Serializable {
  serialize() string
  deserialize(data string) void! // This deserialization might fail!
}
```

### Interface with Parameters (Generic Interfaces): Flexible Contracts
Interfaces can also be generic, allowing them to work with various types while enforcing a consistent structure.

```ms
// A generic 'Repository' interface. 'T' is a placeholder for any type.
// This contract ensures any specific repository (e.g., UserRepository, ProductRepository)
// will have these standard methods for managing items of type 'T'.
interface Repository[T] {
  get(id string) T!             // Get an item of type T by its ID (might error).
  save(item T) void!            // Save an item of type T (might error).
  delete(id string) void!       // Delete by ID (might error).
  list() T[]!                   // List all items of type T (might error).
}
```

## Methods: Giving Your Types Abilities

Methods are functions that are associated with a particular custom type. They operate on an instance of that type.

### Implementing Methods: Teaching Your Types New Tricks
Let's teach our `Rectangle` type how to `draw` itself and calculate its `getArea` and `getPerimeter`.

```ms
type Rectangle {
  width float
  height float
}

// Now we define methods FOR the Rectangle type.
// 'this' refers to the specific instance of Rectangle the method is called on.
methods Rectangle as this { // 'this' is a common name for the instance reference

  draw() void {
    print("Drawing a magnificent rectangle: " + string(this.width) + " wide by " + string(this.height) + " high.")
  }
  
  getArea() float {
    return this.width * this.height // Area = width * height
  }
  
  getPerimeter() float {
    return 2 * (this.width + this.height) // Perimeter = 2 * (width + height)
  }
}

// let rect = Rectangle{width: 10, height: 5}
// rect.draw()
// let area = rect.getArea() // area would be 50
```

### Multiple Interface Implementation: The Talented Type
A single type can promise to fulfill multiple interface contracts by implementing all their required methods.

```ms
// Assuming Rectangle already implements Drawable (draw, getArea, getPerimeter).
// Now, let's also make it Serializable.
methods Rectangle as this { // We can add more methods in another 'methods' block or the same one.

  serialize() string {
    // A simple string representation. JSON would be more common in real life.
    return "Rectangle{width:" + string(this.width) + ",height:" + string(this.height) + "}"
  }
  
  deserialize(data string) void! { // This method can error!
    // In a real scenario, you'd parse 'data' to set 'this.width' and 'this.height'.
    // For example, if data was "Rectangle{width:20,height:10}"
    // This is highly simplified:
    if !data.contains("width:") || !data.contains("height:") {
      error("Invalid data format for Rectangle deserialization: " + data)
    }
    print("Deserialized (pretend) data into rectangle: " + data)
    // this.width = parsedWidth
    // this.height = parsedHeight
  }
}
// Now, a Rectangle instance can be treated as a Drawable AND a Serializable!
```

## Advanced Type Sorcery: Beyond the Basics

For when you need even more power and flexibility from your type system.

### Generic Types: One Blueprint, Many Materials
Create types that can work with any kind of data, specified when you create an instance. The `Container[T]` we saw with generic interfaces is a great example.

```ms
// A generic 'Container' that can hold a value of any type 'T'.
type Container[T] {
  value T // 'T' is a placeholder for the actual type.
  metadata map[string]string // Some extra info about the container.
}

// Multi-line instantiation:
let stringContainer = Container[string]{ // This container holds a string.
  value: "Hello, Generics!"
  metadata: ["type": "text", "source": "example"]
}

// Single-line instantiation:
let intContainer = Container[int]{value: 42, metadata: ["type": "number", "isTheAnswer": "yes"]}
// print(stringContainer.value) // "Hello, Generics!"
// print(intContainer.value)    // 42
```

### Union Types: The "This OR That OR Maybe Another Thing" Type
A union type allows a variable to hold a value of one of several specified types. It's like a variable with multiple personalities.

```ms
// 'Status' can only be one of these three string literals.
type Status = "pending" | "completed" | "failed"

// 'Result' can be an integer, OR a string, OR an Error type (assume Error is defined).
type Result = int | string | Error

fn processResult(result Result) {
  match result { // Pattern matching is perfect for handling union types!
    int: print("Received a number: " + string(result))
    string: print("Received some text: " + result)
    Error: print("Uh oh, an error occurred: " + result.message()) // Assuming Error has a .message()
  }
}

// let myStatus Status = "completed"
// let successResult Result = 100
// let errorResult Result = Error{message: "Something exploded!"}
// processResult(successResult)
// processResult(errorResult)
```

### Nested Types: Blueprints Within Blueprints
You can use custom types as fields within other custom types, creating complex, structured data models.

```ms
// We defined Address earlier. Now Company uses it.
type Company {
  name string
  address Address // Address is another custom type!
  employees Employee[] // An array of Employee types (also custom)!
}

// type Address { street string, city string, zipCode string, country string }
// type Employee { name string, department string } // Simplified for this example

// let myCompany = Company{
//   name: "Awesome Inc.",
//   address: Address{street:"1 Innovation Way", city:"Futureville", zipCode:"90210", country:"Utopia"},
//   employees: [
//     Employee{name:"Alice", department:"R&D"},
//     Employee{name:"Bob", department:"Shenanigans"}
//   ]
// }
```

## Type Validation: Making Sure Things Are What They Seem

Manuscript provides ways to check types at runtime.

### Runtime Type Checking with `typeof` (Conceptual)
You can inspect the underlying type of a value, especially if it's `any` or a union type. (The exact `typeof` syntax might vary or be part of a standard library).

```ms
fn describeValue(value any) string { // 'any' means it could be... anything!
  return match typeof(value) { // typeof(value) would return a string like "string", "int", "User"
    "string": "It's some text: " + value
    "int": "It's a whole number: " + string(value)
    "User": "It's a User named: " + value.name // Assuming 'value' is cast or known to be User here
    default: "It's a mysterious unknown type!"
  }
}
```

### Type Guards: Is It Really a Duck?
A type guard is a function or expression that performs a runtime check and narrows down the type within a certain scope.

```ms
// A type guard function: checks if 'value' is a User.
fn isUser(value any) bool {
  // In a real system, this might involve checking for specific fields or internal type tags.
  // For this example, we'll rely on a conceptual typeof.
  return typeof(value) == "User"
}

fn processIfUser(value any) {
  if isUser(value) {
    // If isUser is true, Manuscript might be smart enough to treat 'value' as User here.
    // This often requires an explicit cast in many languages, e.g., 'value as User'.
    let user = value as User // Explicit cast to User type.
    print("Processing our verified user: " + user.name)
  } else {
    print("Not a user, cannot process as such.")
  }
}
```

## Practical Blueprints: Examples from the Field

Let's see how these concepts come together in more "real-world" scenarios.

### Domain Models: Describing Your World
Defining the core entities of your application.

```ms
type Order {
  id string
  customerId string
  items OrderItem[] // An array of another custom type!
  total float
  status OrderStatus // A union type for status!
  createdAt string
}

type OrderItem {
  productId string
  quantity int
  price float // Price per item at the time of order
}

// Using a union type for specific, allowed statuses.
type OrderStatus = "pending" | "processing" | "shipped" | "delivered" | "cancelled"
```

### Service Interfaces: Defining Service Contracts
What capabilities should your payment or notification services offer?

```ms
// Contract for any Payment Processor
interface PaymentProcessor {
  processPayment(amount float, method PaymentMethod) PaymentResult! // Assume types defined
  refund(transactionId string, amount float) RefundResult!
  getTransactionStatus(id string) TransactionStatus!
}

// Contract for any Notification Service
interface NotificationService {
  sendEmail(to string, subject string, body string) void!
  sendSMS(to string, message string) void!
  sendPush(userId string, title string, body string) void!
}
```

### Repository Pattern: Abstracting Data Access
An interface for data operations (Create, Read, Update, Delete), with concrete implementations for different data stores.

```ms
// The contract for a UserRepository
interface UserRepository {
  create(user User) User!
  getById(id string) User!
  getByEmail(email string) User!
  update(user User) User!
  delete(id string) void!
  list(offset int, limit int) User[]!
}

// A concrete implementation using a (hypothetical) database connection.
type DatabaseUserRepository {
  connection DatabaseConnection // Assume DatabaseConnection is defined
}

// Implementing the UserRepository interface for DatabaseUserRepository
methods DatabaseUserRepository as UserRepository {
  create(user User) User! {
    print("Creating user in DB: " + user.name)
    // ... actual database insert logic using 'this.connection' ...
    return user // Usually return the user with DB-assigned ID, etc.
  }
  
  getById(id string) User! {
    print("Fetching user by ID from DB: " + id)
    // ... actual database select logic ...
    // return User{id: id, name:"Fetched User", ...}
    error("User not found with ID: " + id) // Example error
  }
  
  // ... other methods like getByEmail, update, delete, list would be implemented here ...
  getByEmail(email string) User! { error("Not implemented yet") }
  update(user User) User! { error("Not implemented yet") }
  delete(id string) void! { error("Not implemented yet") }
  list(offset int, limit int) User[]! { error("Not implemented yet") }
}
```

## Architect's Wisdom: Best Practices for Types & Interfaces

A few golden rules from the master builders.

### Type Design Principles
- **Descriptive Names:** Choose names for your types and their fields that are clear and meaningful (e.g., `UserProfile` is better than `UData`).
- **Cohesion:** Keep your types focused. A type should represent a single, well-defined concept. Don't throw unrelated fields into one giant "mega-type."
- **Use Optional Fields Judiciously:** Only make fields optional if they genuinely might not have a value. Avoid making everything optional "just in case."
- **Favor Composition over Deep Inheritance:** While type extension is useful, sometimes composing smaller types together (like `Company` having an `Address` field) leads to more flexible and understandable designs than very long inheritance chains.

### Interface Design Guidelines
- **Clear Contracts:** Interfaces should clearly define what implementing types are expected to do. Method names should be intuitive.
- **Keep Interfaces Small & Focused (ISP - Interface Segregation Principle):** Prefer smaller, more specific interfaces over large, monolithic ones. A type can implement multiple small interfaces.
- **Generics for Reusability:** Use generic interfaces (like `Repository[T]`) when you want to define a contract that can apply to many different underlying data types.
- **Document Behavior:** Comments explaining *what* an interface method is supposed to achieve (and any potential errors it might signal) are incredibly helpful.

### Method Implementation Best Practices
- **Fulfill the Contract:** Ensure your type implements all methods required by any interfaces it claims to adhere to.
- **Meaningful Method Names:** Method names should clearly indicate their action or purpose.
- **Handle Errors Gracefully:** If a method (especially one defined in an interface with `!`) can fail, make sure it signals errors appropriately.
- **Keep Method Logic Focused:** Each method should ideally do one thing well. If a method becomes too long or complex, consider breaking it down.

### Organizing Your Blueprints (Type Organization)
Consider separating your type definitions, interface definitions, and their implementations into logical modules or files, especially in larger projects.

```ms
// Example structure:

// File: types/domain.ms (Your core data blueprints)
export type User { /* ... */ }
export type Order { /* ... */ }

// File: interfaces/services.ms (Contracts for your services)
export interface UserService { /* ... */ }
export interface OrderService { /* ... */ }

// File: implementations/user_service_db.ms (A concrete implementation)
import { User } from '../types/domain.ms'
import { UserService } from '../interfaces/services.ms'
// Assume UserRepository is an interface for data access, also imported.

type DatabaseUserService { // This type implements UserService
  repository UserRepository
}

methods DatabaseUserService as UserService {
  // ... implementation of UserService methods using 'this.repository' ...
}
```
