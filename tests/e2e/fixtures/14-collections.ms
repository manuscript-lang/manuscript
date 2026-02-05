// @test: Collections - Lists and Maps

// === List creation and access ===
let nums = [1, 2, 3, 4, 5]
// @expect: 1
print(nums[0])
// @expect: 5
print(nums[4])
// @expect: 5
print(len(nums))

// === List modification ===
var items = [1, 2, 3]
items.push(4)
// @expect: [1, 2, 3, 4]
print(items)
// @expect: 4
print(len(items))

let popped = items.pop()
// @expect: 4
print(popped)
// @expect: [1, 2, 3]
print(items)

// === List operations ===
let a = [1, 2]
let b = [3, 4]
let combined = concat(a, b)
// @expect: [1, 2, 3, 4]
print(combined)

// @expect: true
print(contains(nums, 3))
// @expect: false
print(contains(nums, 10))

// === Slicing ===
// @expect: [2, 3, 4]
print(slice(nums, 1, 4))
// @expect: [1, 2]
print(take(nums, 2))

// === Sorting ===
let unsorted = [3, 1, 4, 1, 5, 9, 2, 6]
let sorted_asc = sort(unsorted)
// @expect: [1, 1, 2, 3, 4, 5, 6, 9]
print(sorted_asc)
let sorted_desc = reverse(sort(unsorted))
// @expect: [9, 6, 5, 4, 3, 2, 1, 1]
print(sorted_desc)

// === Unique ===
let dups = [1, 2, 2, 3, 3, 3, 4]
// @expect: [1, 2, 3, 4]
print(unique(dups))

// === Reverse ===
// @expect: [5, 4, 3, 2, 1]
print(reverse(nums))

// === Map creation and access ===
let person = {name: "Alice", age: 30, city: "NYC"}
// @expect: Alice
print(person.name)
// @expect: 30
print(person.age)

// === Map operations ===
// @expect: [name, age, city]
print(keys(person))
// @expect: [Alice, 30, NYC]
print(values(person))

// === Nested structures ===
type User
  name: string
  scores: list[number]

let users: list[User] = [User("Alice", [90, 85, 92]), User("Bob", [78, 82, 88])]
// @expect: Alice
print(users[0].name)
// @expect: 85
print(users[0].scores[1])

// === Empty collections ===
let empty_list = []
// @expect: 0
print(len(empty_list))
// @expect: true
print(len(empty_list) == 0)
