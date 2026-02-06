// @test: Type inference and generics e2e

fn identity[T](x: T): T
  x

// @expect: 42
print(identity(42))
// @expect: ok
print(identity("ok"))

type Box[T]
  value: T
  fn get(): T
    value

let b = Box[number](10)
// @expect: 10
print(b.get())

let [a, c] = [1, 2]
// @expect: 1
print(a)
// @expect: 2
print(c)

let { x, y } = { x: 3, y: 4 }
// @expect: 3
print(x)
// @expect: 4
print(y)

fn f(): number
  100

// @expect: 100
print(f())

// @expect: 1
match 1
  1 => print(1)
  _ => print(0)
