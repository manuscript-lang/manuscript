// @test: Inheritance Edge Cases - Type hierarchy stress test

// === Basic type with methods ===
type Entity
  id: number
  fn get_id(): number
    id

let e = Entity(1)
// @expect: 1
print(e.get_id())

// === Method override chain ===
type Base
  fn value(): number
    0

type Middle extends Base
  fn value(): number
    1

type Derived extends Middle
  fn value(): number
    2

let b = Base()
let m = Middle()
let d = Derived()
// @expect: 0
print(b.value())
// @expect: 1
print(m.value())
// @expect: 2
print(d.value())

// === Type with state mutation ===
type Counter2
  value: number = 0
  fn increment()
    value = value + 1
  fn get(): number
    value

let cnt = Counter2()
// @expect: 0
print(cnt.get())
cnt.increment()
// @expect: 1
print(cnt.get())
cnt.increment()
cnt.increment()
// @expect: 3
print(cnt.get())

// === Computed fields ===
type Rectangle2
  width: number
  height: number
  area: () => width * height
  perimeter: () => 2 * (width + height)

let rect = Rectangle2(5, 3)
// @expect: 15
print(rect.area)
// @expect: 16
print(rect.perimeter)

// === Method chaining ===
type Builder
  parts: list[string] = []
  fn add(part: string): Builder
    parts = [...parts, part]
    Builder(parts)
  fn build(): string
    join(parts, "-")

let builder = Builder()
let result = builder.add("a").add("b").add("c")
// @expect: a-b-c
print(result.build())

// === Default values ===
type Config
  host: string = "localhost"
  port: number = 8080

let cfg1 = Config()
// @expect: localhost
print(cfg1.host)
// @expect: 8080
print(cfg1.port)

let cfg2 = Config("example.com", 443)
// @expect: example.com
print(cfg2.host)
// @expect: 443
print(cfg2.port)
