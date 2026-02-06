// @test: Plain types - type declarations with fields and methods

// === Type with default-valued fields (enum-like usage) ===
type Status
  Pending: number = 0
  Active: number = 1
  Complete: number = 2

let status = Status()
// @expect: 0
print(status.Pending)
// @expect: 1
print(status.Active)
// @expect: 2
print(status.Complete)

// === Type with methods ===
type Counter
  value: number = 0
  fn increment(): void
    value = value + 1
  fn get(): number
    value

let c = Counter()
// @expect: 0
print(c.get())
c.increment()
c.increment()
// @expect: 2
print(c.get())

// === Type with optional field and default ===
type Task
  name: string
  priority?: number
  status: string = "pending"
  fn describe(): string
    name + " (" + status + ")"

let t = Task("Build feature")
// @expect: Build feature (pending)
print(t.describe())

// === Type with id and methods ===
type User
  id: number = 1
  fn getId(): number
    id
  fn greet(): string
    "Hello from user " + to_str(id)

let u = User()
// @expect: 1
print(u.getId())
// @expect: Hello from user 1
print(u.greet())

// === Type with multiple methods ===
type Helper
  fn greet(name: string): string
    "Hello, " + name
  fn farewell(name: string): string
    "Goodbye, " + name

let h = Helper()
// @expect: Hello, World
print(h.greet("World"))
// @expect: Goodbye, Friend
print(h.farewell("Friend"))

// === Type with nested object ===
type DbValue
  host: string
  port: number

type DatabaseConfig
  name: string = "postgres"
  value: DbValue

let db = DatabaseConfig("postgres", DbValue("localhost", 5432))
// @expect: postgres
print(db.name)
// @expect: localhost
print(db.value.host)

// === Type with method returning number ===
type MyCounter
  initial: number = 0
  current: number = 10
  fn increment(): number
    current + 1

let mc = MyCounter()
// @expect: 11
print(mc.increment())

// === Type as function argument ===
type Product
  name: string = "Widget"
  price: number = 9.99

fn format_product(p: Product): string
  p.name + ": $" + to_str(p.price)

let prod = Product()
// @expect: Widget: $9.99
print(format_product(prod))

// === Type with method using fields ===
type Point
  x: number
  y: number
  fn distance_from_origin(): number
    sqrt(x ^ 2 + y ^ 2)

let origin = Point(0, 0)
let corner = Point(3, 4)
// @expect: 0
print(origin.distance_from_origin())
// @expect: 5
print(corner.distance_from_origin())

// === Type with method parameters ===
type Calculator
  base: number = 10
  fn add(n: number): number
    base + n
  fn multiply(n: number): number
    base * n

let calc = Calculator()
// @expect: 15
print(calc.add(5))
// @expect: 30
print(calc.multiply(3))

// === Type with list field ===
type TaskQueue
  items: list[string] = ["task1", "task2", "task3"]
  fn size(): number
    len(items)
  fn first_item(): string
    if len(items) > 0 then items[0] else "empty"

let q = TaskQueue()
// @expect: 3
print(q.size())
// @expect: task1
print(q.first_item())

// === Type with map field ===
type Scores
  entries: map[string, number] = {alice: 100, bob: 85, charlie: 92}
  fn lookup(key: string): number
    entries[key] ?? 0

let scores = Scores()
// @expect: 100
print(scores.lookup("alice"))
// @expect: 0
print(scores.lookup("unknown"))
