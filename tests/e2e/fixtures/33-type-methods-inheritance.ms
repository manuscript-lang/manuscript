// @test: Type Methods and Inheritance
import { sqrt } from "std/math"

// === Basic type with methods ===
type Counter
  value: number = 0
  fn increment()
    value = value + 1
  fn get(): number
    value
  fn add(n: number)
    value = value + n

let c = Counter()
// @expect: 0
print(c.get())
c.increment()
// @expect: 1
print(c.get())
c.add(5)
// @expect: 6
print(c.get())

// === Type with methods accessing fields ===
type Rectangle
  width: number
  height: number
  fn area(): number
    width * height
  fn perimeter(): number
    2 * (width + height)
  fn scale(factor: number): Rectangle
    Rectangle(width * factor, height * factor)

let rect = Rectangle(10, 5)
// @expect: 50
print(rect.area())
// @expect: 30
print(rect.perimeter())
let scaled = rect.scale(2)
// @expect: 20 10
print(scaled.width, scaled.height)
// @expect: 200
print(scaled.area())

// === Type with method returning self-type ===
type Vector
  x: number
  y: number
  fn add(other: Vector): Vector
    Vector(x + other.x, y + other.y)
  fn magnitude(): number
    sqrt(x ^ 2 + y ^ 2)
  fn dot(other: Vector): number
    x * other.x + y * other.y

let v1 = Vector(3, 4)
let v2 = Vector(1, 2)
let v3 = v1.add(v2)
// @expect: 4 6
print(v3.x, v3.y)
// @expect: 5
print(v1.magnitude())
// @expect: 11
print(v1.dot(v2))

// === Type with computed fields and methods ===
type Product
  name: string
  price: number
  quantity: number = 1
  total: () => price * quantity
  fn applyDiscount(percent: number): number
    total() * (1 - percent / 100)

let prod = Product("Widget", 10, 5)
// @expect: 50
print(prod.total())
// @expect: 45
print(prod.applyDiscount(10))

// === Multiple instances with methods ===
type BankAccount
  owner: string
  balance: number = 0
  fn deposit(amount: number)
    balance = balance + amount
  fn withdraw(amount: number): bool
    if balance >= amount
      balance = balance - amount
      return true
    false
  fn getBalance(): number
    balance

let acc1 = BankAccount("Alice")
let acc2 = BankAccount("Bob", 100)

acc1.deposit(50)
acc2.deposit(25)
// @expect: 50
print(acc1.getBalance())
// @expect: 125
print(acc2.getBalance())

// @expect: true
print(acc1.withdraw(30))
// @expect: 20
print(acc1.getBalance())
// @expect: false
print(acc1.withdraw(100))

// === Method chaining pattern ===
type Builder
  parts: list[string] = []
  fn addPart(part: string): Builder
    parts.push(part)
    Builder(parts)
  fn build(): string
    join(parts, " + ")

let b = Builder()
let result = b.addPart("A").addPart("B").addPart("C")
// @expect: A + B + C
print(result.build())

// === Type methods with optional params ===
type Greeter
  greeting: string = "Hello"
  fn greet(name: string, excited?: bool): string
    let msg = "{greeting}, {name}"
    if excited then "{msg}!" else msg

let greeter = Greeter()
// @expect: Hello, World
print(greeter.greet("World"))
// @expect: Hello, World!
print(greeter.greet("World", true))

let customGreeter = Greeter("Hi")
// @expect: Hi, Alice
print(customGreeter.greet("Alice"))

// === Type method with multiple parameters ===
type Calculator
  value: number = 0
  fn set(v: number)
    value = v
  fn addValues(a: number, b: number): number
    a + b
  fn multiplyBy(factor: number): number
    value * factor
  fn calculate(op: string, a: number, b: number): number
    match op
      "add" => a + b
      "sub" => a - b
      "mul" => a * b
      "div" => a / b
      _ => 0

let calc = Calculator(10)
// @expect: 50
print(calc.multiplyBy(5))
// @expect: 7
print(calc.addValues(3, 4))
// @expect: 15
print(calc.calculate("add", 10, 5))
// @expect: 20
print(calc.calculate("mul", 4, 5))

// === Type method that modifies state and returns value ===
type Stack
  items: list[number] = []
  fn push(item: number): number
    items.push(item)
    len(items)
  fn pop(): number?
    if len(items) == 0
      return null
    let last = items[len(items) - 1]
    items = items[0:len(items) - 1]
    last
  fn peek(): number?
    if len(items) == 0 then null else items[len(items) - 1]
  fn size(): number
    len(items)

let stack = Stack()
// @expect: 1
print(stack.push(10))
// @expect: 2
print(stack.push(20))
// @expect: 3
print(stack.push(30))
// @expect: 3
print(stack.size())
// @expect: 30
print(stack.peek())
// @expect: 30
print(stack.pop())
// @expect: 20
print(stack.pop())
// @expect: 1
print(stack.size())
