// @test: Destructuring - Object and array destructuring

// === Object destructuring basic ===
let user = {name: "Alice", age: 30, city: "NYC"}
let {name, age} = user
// @expect: Alice
print(name)
// @expect: 30
print(age)

// === Object destructuring all fields ===
let point = {x: 10, y: 20}
let {x, y} = point
// @expect: 10 20
print(x, y)

// === Nested object destructuring ===
let data = {user: {name: "Bob", email: "bob@test.com"}, active: true}
let {user: u} = data
// @expect: Bob
print(u.name)

// === Array destructuring basic ===
let nums = [1, 2, 3, 4, 5]
let [first_num, second_num] = nums
// @expect: 1
print(first_num)
// @expect: 2
print(second_num)

// === Array destructuring with rest ===
let items = [10, 20, 30, 40, 50]
let [head, ...tail] = items
// @expect: 10
print(head)
// @expect: [20, 30, 40, 50]
print(tail)

// === Array destructuring first and rest ===
let letters = ["a", "b", "c", "d"]
let [a, ...rest] = letters
// @expect: a
print(a)
// @expect: [b, c, d]
print(rest)

// === Destructuring in function parameter ===
fn greet_user(user: map)
  let {name} = user
  "Hello, " + (name as string)

// @expect: Hello, Charlie
print(greet_user({name: "Charlie", age: 25}))

// === Destructuring with defaults pattern ===
fn process_config(config: map)
  let name = config.name ?? "default"
  let value = config.value ?? 0
  (name as string) + ": " + to_str(value as number)

// @expect: test: 42
print(process_config({name: "test", value: 42}))
// @expect: default: 0
print(process_config({}))

// === Multiple array destructuring ===
let pair1 = [1, 2]
let pair2 = [3, 4]
let [a1, b1] = pair1
let [a2, b2] = pair2
// @expect: 1 2 3 4
print(a1, b1, a2, b2)

// === Destructuring in loop ===
let pairs = [[1, 2], [3, 4], [5, 6]]
var sum = 0
for pair in pairs
  let [x, y] = pair
  sum = sum + x + y
// @expect: 21
print(sum)

// === Swap using destructuring ===
var left = 10
var right = 20
let [new_left, new_right] = [right, left]
// @expect: 20 10
print(new_left, new_right)

// === Object destructuring with rename ===
let record = {id: 1, name: "Item"}
let {id: record_id, name: record_name} = record
// @expect: 1 Item
print(record_id, record_name)
