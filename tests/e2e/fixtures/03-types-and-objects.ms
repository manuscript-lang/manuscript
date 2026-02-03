// @test: Types and Objects - Data structures

// === Simple type ===
type Point
  x: number
  y: number

let p = Point(3, 4)
// @expect: 3 4
print(p.x, p.y)

// === Functions with types ===
fn distance(p: Point): number
  return sqrt(p.x ^ 2 + p.y ^ 2)

// @expect: 5
print(distance(p))

fn add_points(a: Point, b: Point): Point
  return Point(a.x + b.x, a.y + b.y)

let p2 = Point(2, 3)
let p3 = add_points(p, p2)
// @expect: 5 7
print(p3.x, p3.y)

// === Type with defaults ===
type Config
  name: string
  value: number = 0

let cfg = Config("test")
// @expect: test 0
print(cfg.name, cfg.value)

let cfg2 = Config("test2", 42)
// @expect: test2 42
print(cfg2.name, cfg2.value)

// === Nested objects ===
let nested = {user: {name: "Alice", age: 30}, active: true}
// @expect: Alice
print(nested.user.name)
// @expect: 30
print(nested.user.age)

// === List of objects ===
let items = [{id: 1, value: 10}, {id: 2, value: 20}, {id: 3, value: 30}]
// @expect: 3
print(len(items))
// @expect: 20
print(items[1].value)

// === Map operations ===
let mdata = {a: 1, b: 2, c: 3}
// @expect: [a, b, c]
print(keys(mdata))
// @expect: [1, 2, 3]
print(values(mdata))

// === Clone and modify ===
let original = [1, 2, 3]
var copy = clone(original)
copy.push(4)
// @expect: [1, 2, 3]
print(original)
// @expect: [1, 2, 3, 4]
print(copy)
