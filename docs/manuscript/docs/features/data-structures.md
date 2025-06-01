---
title: "Data Structures: Organizing Your Digital Treasures"
linkTitle: "Data Structures"

description: >
  Explore Manuscript's built-in toolkit for tidying up your data: arrays, objects, maps, sets, and the marvelous custom types.
---

Welcome, esteemed Data Librarians and Digital Curators! Manuscript offers a delightful assortment of built-in structures to help you organize, store, and manage your data with panache. Think of these as different kinds of shelves, boxes, and filing systems for all your valuable information. Let's dive into arrays, objects, maps, sets, and the ever-so-classy custom types.

> Bits and bytes align,
> Order from the chaos springs,
> Data finds its home.

## Arrays: The Neat Rows of Your Data World

Arrays are like numbered lists or shelves where you can store items in a specific order. Simple, yet incredibly effective!

### Array Declaration: Lining Things Up
Here's how you tell Manuscript, "I'd like a list, please!"

```ms
let numbers = [1, 2, 3, 4, 5]             // A classic list of numbers
let names = ["Alice", "Bob", "Charlie"]   // A roll call of distinguished names
let mixed = [1, "hello", true, 3.14]    // Arrays can be a mixed bag of types!
let empty int[] = []                      // An empty list, but it knows it wants integers
```

### Array Access: "I'll Take Item Number Three!"
Getting things out of an array is as easy as knowing its position (index). Remember, computers like to start counting from zero!

```ms
let first = numbers[0]     // Retrieves '1', the esteemed first element
let last = numbers[4]      // Fetches '5', as it's the fifth item (at index 4)
let length = numbers.length()  // Asks "How long is this list?" The answer is 5
```

### Array Methods: Fancy Operations for Your Lists
Arrays come with handy built-in tools.

```ms
let items = [1, 2, 3]
items.append(4)           // Adds 4 to the end: [1, 2, 3, 4]
items.prepend(0)          // Slips 0 in at the beginning: [0, 1, 2, 3, 4]
let removed = items.pop() // Removes and gives you the last element (4 in this case)
let slice = items[1:3]    // Takes a "slice" from index 1 up to (but not including) index 3: [1, 2]
```

## Objects: Your Customizable Data Containers

Objects are like custom-made boxes where you can store related pieces of information, each with its own label (called a key or property).

### Object Declaration: Building Your Box
Define your object and its properties.

```ms
let person = {
  name: "Alice", // Property 'name' holds the value "Alice"
  age: 30,       // Property 'age' holds 30
  city: "New York" // And so on...
}

let empty = {}  // An empty box, ready for treasures!
```

### Object Access: Getting and Setting Goodies
Retrieve or update the information within your object.

```ms
let name = person.name     // "Alice" - dot notation is quite stylish
let age = person["age"]    // 30 - bracket notation also works, handy for dynamic keys
person.email = "alice@example.com"  // "Oh, I forgot the email!" Let's add it.
```

### Nested Objects: Boxes Within Boxes!
Objects can contain other objects (and arrays!), letting you build complex data hierarchies. It's like a Russian doll, but with data.

```ms
let company = {
  name: "Tech Corp Deluxe",
  address: { // An object within an object!
    street: "123 Main St",
    city: "San Francisco",
    zipCode: "94105"
  },
  employees: [ // An array of objects!
    { name: "Alice", role: "Chief Innovator" },
    { name: "Bob", role: "Master of Coffee" }
  ]
}

let street = company.address.street // Digging deep to get "123 Main St"
let firstEmployeeName = company.employees[0].name // Accessing the first employee's name: "Alice"
```

## Maps: The Key-Value Emporium

Maps are collections where you store pairs of keys and values. Think of them as dictionaries or lookup tables. Manuscript maps let you specify types for both keys and values.

### Map Declaration: Setting Up Your Directory
Keys can be various types, not just strings (though string keys are common).

```ms
let scores = ["Alice": 95, "Bob": 87, "Charlie": 92] // String keys, integer values
let ages = ["Alice": 30, "Bob": 25, "Charlie": 35]     // More string keys
let empty = [:]                                       // An empty map, awaiting entries
```

### Map Operations: Managing Your Key-Value Pairs
Adding, removing, and checking for entries.

```ms
let aliceScore = scores["Alice"]  // Retrieves 95. What a score!
scores["David"] = 88              // Welcome, David, to the score map!
scores.remove("Bob")              // Sorry, Bob, your score has been expunged.
let hasAlice = scores.contains("Alice")  // Is Alice still in our records? (true)
let keys = scores.keys()          // Get a list of all keys: ["Alice", "Charlie", "David"]
let values = scores.values()      // Get a list of all values: [95, 92, 88]
```

### Iterating Maps: A Stroll Through Your Directory
Visiting each key-value pair.

```ms
// Just the keys
for key in scores {
  print(key + " has a score of: " + string(scores[key]))
}

// Both key and value, very convenient!
for key, value in scores {
  print(key + " officially scored " + string(value) + " points.")
}
```

## Sets: The Guardians of Uniqueness

Sets are collections that only store unique values. If you try to add something that's already there, the set just yawns and ignores you.

### Set Declaration: Establishing Your Exclusive Club
Use angle brackets `< >` for sets.

```ms
let numbers = <1, 2, 3, 4, 5>         // Each number here is unique, naturally
let names = <"Alice", "Bob", "Charlie"> // Alice can only be in this set once
let empty = <>                          // An empty set, ready for unique members
```

### Set Operations: Playing with Uniqueness
Adding, removing, checking membership, and cool mathematical set operations.

```ms
numbers.add(6)           // Adds 6: <1, 2, 3, 4, 5, 6>
numbers.add(1)           // Tries to add 1 again... set remains <1, 2, 3, 4, 5, 6>. No duplicates allowed!
numbers.remove(3)        // Removes 3: <1, 2, 4, 5, 6>
let hasTwo = numbers.contains(2)  // Does the set have a 2? (true)
let size = numbers.size()         // How many unique items? (5)

// Now for some fancy set theory!
let a = <1, 2, 3>
let b = <3, 4, 5>
let unionSet = a.union(b)        // All unique items from both: <1, 2, 3, 4, 5>
let intersectionSet = a.intersect(b)  // Items present in both: <3>
let differenceSet = a.subtract(b)     // Items in 'a' but not in 'b': <1, 2>
```

## Custom Types: Designing Your Own Data Blueprints

Sometimes, the built-in structures aren't quite enough. You want to define your own kind of data container with specific fields and types. Enter custom types!

### Type Definition: Creating the Blueprint
Use the `type` keyword to define your own data structure.

```ms
type Person { // Our very own "Person" blueprint
  name string
  age int
  email string
  isAwesome bool // Default to true, obviously
}

type Address { // Another blueprint for addresses
  street string
  city string
  zipCode string
}
```

### Creating Instances: Bringing Your Blueprints to Life
Once defined, you can create "instances" of your custom types.

```ms
let alice = Person{
  name: "Alice Johnson",
  age: 30,
  email: "alice@example.com",
  isAwesome: true
}

let homeAddress = Address{
  street: "123 Enchanted Lane",
  city: "Manuscriptville",
  zipCode: "12345"
}
```

### Optional Fields: "Maybe You Have It, Maybe You Don't"
Sometimes a field isn't strictly required. Mark it with a `?`.

```ms
type Product {
  name string
  price float
  description string?  // The '?' means description is optional
  tags string[]
}

let shinyLaptop = Product{
  name: "SuperFast Laptop X2000",
  price: 999.99,
  tags: ["electronics", "computers", "shiny"]
  // description is omitted, and that's perfectly fine!
}

let anotherProduct = Product{
  name: "Mysterious Artifact",
  price: 10000.00,
  description: "Its purpose is unknown, but it glows faintly.", // This one has a description
  tags: ["rare", "magical"]
}
```

## Tuples: Simple Group Hugs for Your Data

Tuples are fixed-size, ordered collections that can hold values of different types. Think of them as lightweight containers for small groups of related data.

```ms
let point = (10, 20)              // A 2D point: (int, int)
let personInfo = ("Alice", 30, true)  // A mixed bag: (string, int, bool)
let variousData = (1, "hello", 3.14, false)

// Destructuring tuples is super convenient!
let (x, y) = point // x gets 10, y gets 20
let (name, age, isActive) = personInfo // name is "Alice", age is 30, isActive is true
```

## Collection Operations: Power Tools for Your Data

Manuscript provides some nifty functional-style operations for working with collections.

### Functional Operations: Map, Filter, Reduce, Find - Oh My!

```ms
let numbers = [1, 2, 3, 4, 5]

// Map - Create a new array by transforming each element.
// Let's double every number, just for kicks.
let doubled = numbers.map(fn(x) {  x * 2 })  // Result: [2, 4, 6, 8, 10]

// Filter - Create a new array with only the elements that pass your test.
// Let's find all the even numbers.
let evens = numbers.filter(fn(x) {  x % 2 == 0 })  // Result: [2, 4]

// Reduce - Boil down all elements into a single value.
// Let's sum them all up. (Starts with an initial accumulator value of 0)
let sum = numbers.reduce(0, fn(accumulator, x) {  accumulator + x })  // Result: 15

// Find - Get the first element that matches your condition.
// Let's find the first number greater than 3.
let found = numbers.find(fn(x) {  x > 3 })  // Result: 4 (it stops at the first match)
```

### Sorting: Putting Things in Order
Because sometimes, order is everything.

```ms
let names = ["Charlie", "Alice", "Bob"]
names.sort()  // Sorts them alphabetically (in-place): ["Alice", "Bob", "Charlie"]

let numbersToSort = [3, 1, 4, 1, 5, 9, 2, 6] // A jumble of numbers
// Sort with a custom comparison function for ascending order
numbersToSort.sort(fn(a, b) {  a - b })  // Result: [1, 1, 2, 3, 4, 5, 6, 9]
```

## Advanced Patterns: Showing Off Your Organizational Skills

### Collection Comprehensions: Building Collections Concisely
A fancy, Python-esque way to create arrays or maps based on existing collections.

```ms
// Array comprehension: Give me squares of even numbers from 0 to 9
let squares = [x * x for x in range(10) if x % 2 == 0]  // Result: [0, 4, 16, 36, 64]

// Map comprehension: Create a map of words to their lengths
let wordLengths = [word: word.length() for word in ["hello", "world", "manuscript", "is", "fun"]]
// Result: ["hello": 5, "world": 5, "manuscript": 10, "is": 2, "fun": 3]
```

### Nested Data Structures: The Russian Dolls of Data
You can nest these structures as deep as you dare, creating complex information landscapes.

```ms
// A matrix (an array of arrays) representing a 2D grid
let matrix = [
  [1, 2, 3],
  [4, 5, 6],
  [7, 8, 9]
]

let centerValue = matrix[1][2]  // Accesses the 6 (row 1, column 2)

// A more complex example of nesting for an organization chart
let organization = {
  departments: [
    {
      name: "Galactic Engineering",
      teams: [
        { name: "Warp Drive Maintenance", members: ["Alice", "Bob"] },
        { name: "Holodeck Programming", members: ["Charlie", "David", "Eve"] }
      ]
    },
    {
      name: "Planetary Catering",
      teams: [
        { name: "Alien Cuisine", members: ["Frank", "Grace"] }
      ]
    }
  ]
}
let holodeckLead = organization.departments[0].teams[1].members[0] // Charlie
```

## Curator's Corner: Best Practices for Data Structuring

A few words of wisdom to keep your data exhibits pristine and your code elegant.

### Performance Pointers
- **Arrays** are your go-to for ordered lists where you often access items by their numerical index.
- **Maps** shine for quick key-value lookups (especially with string keys, but Manuscript is flexible!).
- **Sets** are unbeatable for ensuring uniqueness and speedy membership tests (is this item in the collection?).
- **Custom types** are great for giving meaningful structure to your data, which can also help with clarity and sometimes even performance if the system can optimize known shapes.

### Memory Management Musings
- When you can, use arrays with a specific type (e.g., `int[]`) rather than `any[]` if all elements are the same. It can be more memory-efficient and safer.
- If you only need a few fields from a large object, consider using object destructuring to extract just what you need, rather than passing the whole behemoth around.
- For very large collections that are no longer needed, ensure they go out of scope or are otherwise cleared to free up memory (Manuscript's garbage collector helps, but good habits don't hurt!).

### Readability & Clarity Rules
- Choose descriptive names for your data structures (e.g., `userScores` is better than `s` or `dataMap`).
- Custom types are your friends for complex data. `let user = User{...}` is much clearer than `let user = {name: "X", id: 123, ...}` especially when passed between functions.
- Use the appropriate collection methods (like `map`, `filter`, `reduce`) for transformations; they often make your intent clearer than manual loops.
