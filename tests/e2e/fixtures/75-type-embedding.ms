// @test: Type Embedding - Go-style composition
import { keys } from "std/collections"

// === Basic Embedding ===
type Animal
  name: string
  age: number
  
  fn speak(): string
    "{name} says hello"

type Dog
  Animal
  breed: string
  
  fn bark(): string
    "{name} barks!"

let dog = Dog(Animal("Buddy", 3), "Golden Retriever")
// @expect: Buddy
print(dog.name)
// @expect: 3
print(dog.age)
// @expect: Golden Retriever
print(dog.breed)
// @expect: Buddy says hello
print(dog.speak())
// @expect: Buddy barks!
print(dog.bark())

// === Direct Access to Embedded Type ===
// @expect: Buddy
print(dog.Animal.name)
// @expect: 3
print(dog.Animal.age)

// === Multiple Embedding ===
type Named
  name: string

type Aged
  age: number

type Person
  Named
  Aged
  occupation: string

let person = Person(Named("Alice"), Aged(30), "Engineer")
// @expect: Alice
print(person.name)
// @expect: 30
print(person.age)
// @expect: Engineer
print(person.occupation)

// === Method Promotion ===
type Logger
  prefix: string
  
  fn log(msg: string): string
    "{prefix}: {msg}"
  
  fn warn(msg: string): string
    "{prefix} WARNING: {msg}"

type AppLogger
  Logger
  appName: string
  
  fn info(msg: string): string
    log("[{appName}] {msg}")

let logger = AppLogger(Logger("APP"), "MyApp")
// @expect: APP: hello
print(logger.log("hello"))
// @expect: APP WARNING: danger
print(logger.warn("danger"))
// @expect: APP: [MyApp] starting
print(logger.info("starting"))

// === Shadowing - Child Overrides Embedded ===
type Base
  value: number = 10
  
  fn getValue(): number
    value

type Derived
  Base
  value: number = 20
  
  fn getValue(): number
    value * 2

let derived = Derived()
// Child's value shadows embedded
// @expect: 20
print(derived.value)
// @expect: 40
print(derived.getValue())
// Can still access embedded via type name
// @expect: 10
print(derived.Base.value)

// === Embedding with Default Values ===
type Config
  timeout: number = 1000
  retries: number = 3

type ServerConfig
  Config
  host: string = "localhost"
  port: number = 8080

let config = ServerConfig()
// @expect: 1000
print(config.timeout)
// @expect: 3
print(config.retries)
// @expect: localhost
print(config.host)
// @expect: 8080
print(config.port)

// Override embedded defaults
let custom = ServerConfig(Config(500, 5), "example.com", 443)
// @expect: 500
print(custom.timeout)
// @expect: example.com
print(custom.host)

// === Nested Embedding ===
type Timestamps
  created: number = 0
  updated: number = 0

type Auditable
  Timestamps
  createdBy: string = "system"

type Document
  Auditable
  title: string
  content: string

let doc = Document(Auditable(Timestamps(100, 200), "admin"), "My Doc", "Hello World")
// @expect: 100
print(doc.created)
// @expect: 200
print(doc.updated)
// @expect: admin
print(doc.createdBy)
// @expect: My Doc
print(doc.title)

// Direct access through chain
// @expect: 100
print(doc.Auditable.created)
// @expect: 100
print(doc.Auditable.Timestamps.created)

// === Keys and Iteration ===
fn count_fields(obj: map[unknown, unknown]): number
  len(keys(obj))

// keys() returns own enumerable keys including promoted
let animal = Animal("Cat", 5)
// @expect: Cat
print(animal.name)

// === Embedding with Methods that Use Fields ===
type Counter
  count: number = 0
  
  fn increment(): number
    count = count + 1
    count
  
  fn decrement(): number
    count = count - 1
    count

type BoundedCounter
  Counter
  max: number
  
  fn increment(): number
    if count < max
      count = count + 1
    count

let bc = BoundedCounter(Counter(), 5)
// @expect: 1
print(bc.increment())
// @expect: 2
print(bc.increment())
// @expect: 3
print(bc.increment())
// @expect: 4
print(bc.increment())
// @expect: 5
print(bc.increment())
// @expect: 5
print(bc.increment())
// Capped at max
// @expect: 5
print(bc.count)
