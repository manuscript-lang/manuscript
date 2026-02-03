// @test: Operators - Arithmetic and Comparison

// === Arithmetic operators ===
// @expect: 15
print(10 + 5)
// @expect: 5
print(10 - 5)
// @expect: 50
print(10 * 5)
// @expect: 2
print(10 / 5)
// @expect: 1
print(10 % 3)
// @expect: 1000
print(10 ^ 3)

// === Comparison operators ===
// @expect: true
print(5 < 10)
// @expect: false
print(10 < 5)
// @expect: true
print(10 > 5)
// @expect: true
print(5 <= 5)
// @expect: true
print(5 >= 5)
// @expect: true
print(5 == 5)
// @expect: true
print(5 != 10)

// === Logical operators ===
// @expect: true
print(true and true)
// @expect: false
print(true and false)
// @expect: true
print(true or false)
// @expect: false
print(false or false)
// @expect: false
print(not true)
// @expect: true
print(not false)

// === Short-circuit evaluation ===
fn returns_true(): bool
  print("evaluated true")
  true

fn returns_false(): bool
  print("evaluated false")
  false

// Short-circuit AND
// @expect: evaluated false
// @expect: false
print(returns_false() and returns_true())

// Short-circuit OR
// @expect: evaluated true
// @expect: true
print(returns_true() or returns_false())

// === String concatenation ===
// @expect: hello world
print("hello" + " " + "world")

// === Compound assignment ===
var x = 10
x += 5
// @expect: 15
print(x)
x -= 3
// @expect: 12
print(x)
x *= 2
// @expect: 24
print(x)
x /= 4
// @expect: 6
print(x)
x %= 4
// @expect: 2
print(x)

// === Negation ===
// @expect: -5
print(-5)
let n = 10
// @expect: -10
print(-n)

// === Null coalescing ===
let maybe_null: string? = null
// @expect: default
print(maybe_null ?? "default")
let has_value: string? = "value"
// @expect: value
print(has_value ?? "default")
