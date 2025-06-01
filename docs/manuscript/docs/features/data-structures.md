---
title: "Data Structures"
linkTitle: "Data Structures"

description: >
  Arrays, objects, maps, sets, and custom types in manuscript.
---

Your data called, it's tired of floating around aimlessly! Data structures are here to give your information some shape, order, and a cozy place to live. Think of them as the organizational gurus for your program's bits and pieces.

## Arrays
Arrays: the good old conga line of data! Everything in order, one after another. Perfect when you need to keep your ducks (or numbers, or strings) in a row.

Orderly items,
Indexed for a quick find,
A neat, tidy list.

### Array Declaration
```ms
let numbers = [1, 2, 3, 4, 5]
let names = ["Alice", "Bob", "Charlie"]
let mixed = [1, "hello", true, 3.14] // Arrays: not picky about types by default!
let empty int[] = []  // empty array with explicit type // An empty box, but it *knows* it's for ints.
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
let removed = items.pop() // removes and returns last element // Bye bye, last element!
let slice = items[1:3]    // [1, 2]
```

## Objects
Objects are like customizable name tags for your data. Instead of just a value, you get a collection of `name: value` pairs. 'Hello, my name is... Person, and my age is... 30!'

### Object Declaration
```ms
let person = {
  name: "Alice",
  age: 30,
  city: "New York"
}

let empty = {}  // empty object // A blank slate, ready for properties!
```

### Object Access
```ms
let name = person.name     // "Alice"
let age = person["age"]    // 30 (bracket notation)
person.email = "alice@example.com"  // add new field // Easy to add new things!
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
Maps are your program's super-organized dictionary or address book. Got a key (like a word or a name)? The map will tell you its value (like a definition or a phone number). Super speedy lookups!
Maps provide key-value storage with typed keys and values:

### Map Declaration
```ms
let scores = ["Alice": 95, "Bob": 87, "Charlie": 92]
let ages = ["Alice": 30, "Bob": 25, "Charlie": 35]
let empty = [:]  // empty map // An empty map, hungry for key-value pairs.
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
Sets are the bouncers of the data world – no duplicates allowed! If you try to add something that's already in there, the set just shrugs. 'Heard it, got it, no need for another one.'

Unique things reside,
No repeats in this cool club,
Order matters not.

### Set Declaration
```ms
let numbers = <1, 2, 3, 4, 5>
let names = <"Alice", "Bob", "Charlie">
let empty = <>  // empty set // An empty set, yearning for unique items.
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
let union = a.union(b)        // <1, 2, 3, 4, 5> // All together now!
let intersection = a.intersect(b)  // <3>
let difference = a.subtract(b)     // <1, 2>
```

## Custom Types
Feeling creative? With custom types, you're the architect! Design your own data blueprints, combining existing types to perfectly model your world. Your program, your rules!

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
  // description is omitted (optional) // No description? No problem!
}
```

## Tuples
Tuples are like little grab-bags of data. A string here, a number there, a boolean for good measure. They're simple, fixed-size groups for when you just need to bundle a few different things together.

Tuples group related values of different types:

```ms
let point = (10, 20)              // (int, int)
let person = ("Alice", 30, true)  // (string, int, bool)
let mixed = (1, "hello", 3.14, false)

// Destructuring
let (x, y) = point
let (name, age, active) = person // Unpacking the tuple like a gift!
```

## Collection Operations
Once you've got your data nicely structured, it's time to party! Manuscript offers powerful tools to transform, filter, and wrangle your collections.

### Functional Operations
```ms
let numbers = [1, 2, 3, 4, 5]

// Map - transform each element
let doubled = numbers.map(fn(x) {  x * 2 })  // [2, 4, 6, 8, 10] // Each number, times two!

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
Ready to level up your data game? Comprehensions are a fancy way to build collections, and nesting lets you create data structures within data structures – it's like Inception, but for your data!

### Collection Comprehensions
```ms
// Array comprehension
let squares = [x * x for x in range(10) if x % 2 == 0]  // [0, 4, 16, 36, 64] // Building a list, the fancy way.

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