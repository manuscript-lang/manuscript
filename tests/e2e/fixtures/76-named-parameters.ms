// @test: Named Parameters - fn and type constructors with name: value args

// === Function with named params (reordered) ===
fn greet(first: string, second: string): string
  first + " " + second

let a = greet(second: "Bar", first: "Foo")
// @expect: Foo Bar
print(a)

// === Type constructor with named params ===
type Person
  name: string
  age: number

let p = Person(age: 30, name: "Alice")
// @expect: Alice
print(p.name)
// @expect: 30
print(p.age)

// === Type with optional/default and named params ===
type Config
  env: string
  debug: bool = false

let cfg = Config(env: "prod", debug: true)
// @expect: prod
print(cfg.env)
// @expect: true
print(cfg.debug)

// @expect: named params ok
print("named params ok")

// Named Parameters Errors - mixed positional and named not allowed

fn triple(a: number, b: number, c: number): number
  a + b + c

// @error: Cannot mix positional and named arguments
let x = triple(10, c: 30, b: 20)

print(x)

