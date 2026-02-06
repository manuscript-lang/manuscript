// @test: Keywords - Extensible keyword system

// === Basic enum keyword ===
enum Status
  Pending = 0
  Active = 1
  Complete = 2

// @expect: 0
print(Status.Pending)
// @expect: 1
print(Status.Active)
// @expect: 2
print(Status.Complete)

// === Enum with string values ===
enum Color
  Red = "red"
  Green = "green"
  Blue = "blue"

// @expect: red
print(Color.Red)
// @expect: green
print(Color.Green)

// === Custom keyword declaration ===
keyword workflow = type
  steps: list[string]
  
  fn run(): void
    for step in steps
      print("Running: " + step)

// === Keyword type use with value assignment ===
workflow Pipeline
  steps = ["fetch", "transform", "load"]

let p = Pipeline()
// @expect: Running: fetch
// @expect: Running: transform
// @expect: Running: load
p.run()

// === Keyword with optional field and default ===
keyword task = type
  name: string
  priority?: number
  status: string = "pending"
  
  fn describe(): string
    name + " (" + status + ")"

task MyTask
  name = "Build feature"

let t = MyTask()
// @expect: Build feature (pending)
print(t.describe())

// === User adding methods to keyword type ===
keyword entity = type
  id: number
  
  fn getId(): number
    id

entity User
  id = 1
  
  fn greet(): string
    "Hello from user " + to_str(id)

let u = User()
// @expect: 1
print(u.getId())
// @expect: Hello from user 1
print(u.greet())

// === Agent keyword with methods ===
agent Helper
  fn greet(name: string): string
    "Hello, " + name
  
  fn farewell(name: string): string
    "Goodbye, " + name

let h = Helper()
// @expect: Hello, World
print(h.greet("World"))
// @expect: Goodbye, Friend
print(h.farewell("Friend"))

// === Nested keyword usage ===
keyword config = type
  name: string
  value: unknown

config DatabaseConfig
  name = "postgres"
  value = {host: "localhost", port: 5432}

let db = DatabaseConfig()
// @expect: postgres
print(db.name)
// @expect: localhost
print(db.value.host)

// === Keyword with computed expressions in values ===
keyword counter = type
  initial: number
  current: number
  
  fn increment(): number
    current + 1

counter MyCounter
  initial = 0
  current = 10

let c = MyCounter()
// @expect: 11
print(c.increment())

// === Keyword instances as function arguments ===
keyword item = type
  name: string
  price: number

item Product
  name = "Widget"
  price = 9.99

fn format_product(p: Product): string
  p.name + ": $" + to_str(p.price)

let prod = Product()
// @expect: Widget: $9.99
print(format_product(prod))

// === Multiple keyword instances ===
keyword point = type
  x: number
  y: number
  
  fn distance_from_origin(): number
    sqrt(x ^ 2 + y ^ 2)

point Origin
  x = 0
  y = 0

point Corner
  x = 3
  y = 4

let o = Origin()
let corner = Corner()
// @expect: 0
print(o.distance_from_origin())
// @expect: 5
print(corner.distance_from_origin())

// === Keyword method with parameters ===
keyword calculator = type
  base: number
  
  fn add(n: number): number
    base + n
  
  fn multiply(n: number): number
    base * n

calculator Calc
  base = 10

let calc = Calc()
// @expect: 15
print(calc.add(5))
// @expect: 30
print(calc.multiply(3))

// === Keyword with list field operations ===
keyword queue = type
  items: list[string]
  
  fn size(): number
    len(items)
  
  fn first_item(): string
    if len(items) > 0 then items[0] else "empty"

queue TaskQueue
  items = ["task1", "task2", "task3"]

let q = TaskQueue()
// @expect: 3
print(q.size())
// @expect: task1
print(q.first_item())

// === Keyword with map field ===
keyword registry = type
  entries: map[string, number]
  
  fn lookup(key: string): number
    entries[key] ?? 0

registry Scores
  entries = {alice: 100, bob: 85, charlie: 92}

let scores = Scores()
// @expect: 100
print(scores.lookup("alice"))
// @expect: 0
print(scores.lookup("unknown"))


// === Enum without explicit value ===
enum BadEnum
  Red
// @error: Expected
