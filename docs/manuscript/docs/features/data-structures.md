---
title: "Data Structures"
linkTitle: "Data Structures"
weight: 40
description: >
  Arrays, objects, maps, sets, and custom types in manuscript.
---

manuscript provides several built-in data structures for organizing and manipulating data: arrays, objects, maps, sets, and custom types.

## Arrays

### Array Declaration
```ms
let numbers = [1, 2, 3, 4, 5]
let names = ["Alice", "Bob", "Charlie"]
let mixed = [1, "hello", true, 3.14]
let empty int[] = []  // empty array with explicit type
```

### Array Access
```ms
let first = numbers[0]     // 1
let last = numbers[4]      // 5
let length = numbers.length()  // 5
```

### Array Methods
```ms
let items = [1, 2, 3]
items.append(4)           // [1, 2, 3, 4]
items.prepend(0)          // [0, 1, 2, 3, 4]
let removed = items.pop() // removes and returns last element
let slice = items[1:3]    // [1, 2]
```

## Objects

### Object Declaration
```ms
let person = {
  name: "Alice",
  age: 30,
  city: "New York"
}

let empty = {}  // empty object
```

### Object Access
```ms
let name = person.name     // "Alice"
let age = person["age"]    // 30 (bracket notation)
person.email = "alice@example.com"  // add new field
```

### Nested Objects
```ms
let company = {
  name: "Tech Corp",
  address: {
    street: "123 Main St",
    city: "San Francisco",
    zipCode: "94105"
  },
  employees: [
    { name: "Alice", role: "Engineer" },
    { name: "Bob", role: "Designer" }
  ]
}

let street = company.address.street
let firstEmployee = company.employees[0].name
```

## Maps

Maps provide key-value storage with typed keys and values:

### Map Declaration
```ms
let scores = ["Alice": 95, "Bob": 87, "Charlie": 92]
let ages = ["Alice": 30, "Bob": 25, "Charlie": 35]
let empty = [:]  // empty map
```

### Map Operations
```ms
let aliceScore = scores["Alice"]  // 95
scores["David"] = 88              // add new entry
scores.remove("Bob")              // remove entry
let hasAlice = scores.contains("Alice")  // true
let keys = scores.keys()          // ["Alice", "Charlie", "David"]
let values = scores.values()      // [95, 92, 88]
```

### Iterating Maps
```ms
for key in scores {
  print(key + ": " + string(scores[key]))
}

for key, value in scores {
  print(key + " scored " + string(value))
}
```

## Sets

Sets store unique values:

### Set Declaration
```ms
let numbers = <1, 2, 3, 4, 5>
let names = <"Alice", "Bob", "Charlie">
let empty = <>  // empty set
```

### Set Operations
```ms
numbers.add(6)           // <1, 2, 3, 4, 5, 6>
numbers.remove(3)        // <1, 2, 4, 5, 6>
let hasTwo = numbers.contains(2)  // true
let size = numbers.size()         // 5

// Set operations
let a = <1, 2, 3>
let b = <3, 4, 5>
let union = a.union(b)        // <1, 2, 3, 4, 5>
let intersection = a.intersect(b)  // <3>
let difference = a.subtract(b)     // <1, 2>
```

## Custom Types

### Type Definition
```ms
type Person {
  name string
  age int
  email string
}

type Address {
  street string
  city string
  zipCode string
}
```

### Creating Instances
```ms
let alice = Person{
  name: "Alice Johnson",
  age: 30,
  email: "alice@example.com"
}

let address = Address{
  street: "123 Main St",
  city: "San Francisco",
  zipCode: "94105"
}
```

### Optional Fields
```ms
type Product {
  name string
  price float
  description string?  // optional field
  tags string[]
}

let product = Product{
  name: "Laptop",
  price: 999.99,
  tags: ["electronics", "computers"]
  // description is omitted (optional)
}
```

## Tuples

Tuples group related values of different types:

```ms
let point = (10, 20)              // (int, int)
let person = ("Alice", 30, true)  // (string, int, bool)
let mixed = (1, "hello", 3.14, false)

// Destructuring
let (x, y) = point
let (name, age, active) = person
```

## Collection Operations

### Functional Operations
```ms
let numbers = [1, 2, 3, 4, 5]

// Map - transform each element
let doubled = numbers.map(fn(x) {  x * 2 })  // [2, 4, 6, 8, 10]

// Filter - keep elements that match condition
let evens = numbers.filter(fn(x) {  x % 2 == 0 })  // [2, 4]

// Reduce - combine elements into single value
let sum = numbers.reduce(0, fn(acc, x) {  acc + x })  // 15

// Find - first element matching condition
let found = numbers.find(fn(x) {  x > 3 })  // 4
```

### Sorting
```ms
let names = ["Charlie", "Alice", "Bob"]
names.sort()  // ["Alice", "Bob", "Charlie"]

let numbers = [3, 1, 4, 1, 5]
numbers.sort(fn(a, b) {  a - b })  // [1, 1, 3, 4, 5]
```

## Advanced Patterns

### Collection Comprehensions
```ms
// Array comprehension
let squares = [x * x for x in range(10) if x % 2 == 0]  // [0, 4, 16, 36, 64]

// Map comprehension  
let wordLengths = [word: word.length() for word in ["hello", "world", "manuscript"]]
```

### Nested Data Structures
```ms
let matrix = [
  [1, 2, 3],
  [4, 5, 6],
  [7, 8, 9]
]

let value = matrix[1][2]  // 6

// Complex nesting
let organization = {
  departments: [
    {
      name: "Engineering",
      teams: [
        { name: "Frontend", members: ["Alice", "Bob"] },
        { name: "Backend", members: ["Charlie", "David"] }
      ]
    }
  ]
}
```

## Best Practices

### Performance
- Use arrays for ordered data and frequent index access
- Use maps for key-value lookups with string keys
- Use sets for unique value storage and membership testing
- Consider custom types for structured data

### Memory
- Prefer specific types over mixed arrays when possible
- Use object destructuring to extract needed fields
- Clear large collections when no longer needed

### Readability
- Use descriptive names for data structures
- Consider custom types for complex data
- Use appropriate collection methods for transformations 