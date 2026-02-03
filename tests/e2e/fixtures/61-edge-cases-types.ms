// @test: Type Inference Edge Cases - Complex type scenarios

// === Recursive type definition ===
type Node
  value: number
  children: list[Node]

fn sum_tree(node: Node): number
  var total = node.value
  for child in node.children
    total = total + sum_tree(child)
  total

let tree = Node(1, [Node(2, []), Node(3, [Node(4, [])])])
// @expect: 10
print(sum_tree(tree))

// === Mutually referential types ===
type Person
  name: string
  friends: list[Person]

let alice = Person("Alice", [])
let bob = Person("Bob", [alice])
// @expect: Alice
print(bob.friends[0].name)

// === Optional chaining with fallback ===
type Config
  db: DbConfig?

type DbConfig
  host: string
  port: number

fn get_host(cfg: Config): string
  match cfg.db
    null => "localhost"
    DbConfig as db => db.host

let cfg1 = Config(DbConfig("remote.host", 5432))
let cfg2 = Config(null)
// @expect: remote.host
print(get_host(cfg1))
// @expect: localhost
print(get_host(cfg2))

// === Higher-order functions ===
fn apply_twice(f: fn(number): number, x: number): number
  f(f(x))

fn add_ten(n: number): number
  n + 10

// @expect: 25
print(apply_twice(add_ten, 5))

// === Closure captures ===
fn make_adder(base: number): fn(number): number
  (n) => base + n

let add5 = make_adder(5)
// @expect: 8
print(add5(3))
// @expect: 15
print(add5(10))

// === Complex return type inference ===
fn weird_return(n: number)
  if n > 0
    return "positive"
  if n < 0
    return "negative"
  "zero"

// @expect: positive
print(weird_return(5))
// @expect: negative
print(weird_return(-5))
// @expect: zero
print(weird_return(0))

// === Nested generic collections ===
let matrix: list[list[number]] = [[1, 2], [3, 4], [5, 6]]
var flat_sum = 0
for row in matrix
  for cell in row
    flat_sum = flat_sum + cell
// @expect: 21
print(flat_sum)

// === Map with string keys ===
let str_map: map[string, number] = {"a": 1, "b": 2}
// @expect: 1
print(str_map["a"])

// === Default parameter handling ===
fn greet_with_default(name: string, greeting: string = "Hello"): string
  "{greeting}, {name}!"

// @expect: Hello, Alice!
print(greet_with_default("Alice"))
// @expect: Hi, Bob!
print(greet_with_default("Bob", "Hi"))

// === Variadic function ===
fn sum_all(...nums: list[number]): number
  var total = 0
  for n in nums
    total = total + n
  total

// @expect: 15
print(sum_all(1, 2, 3, 4, 5))
// @expect: 0
print(sum_all())

// === Type with methods ===
type Counter
  value: number = 0
  fn get(): number
    value
  fn increment(): number
    value = value + 1
    value

let c = Counter()
// @expect: 0
print(c.get())
// @expect: 1
print(c.increment())
// @expect: 2
print(c.increment())
