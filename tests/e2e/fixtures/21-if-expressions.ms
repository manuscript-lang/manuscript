// @test: If Expressions - If as expression returning values

// === Basic if expression ===
let x = 10
let result = if x > 5 then "big" else "small"
// @expect: big
print(result)

// === If expression with numbers ===
let n = 42
let doubled = if n % 2 == 0 then n * 2 else n
// @expect: 84
print(doubled)

// === Nested if expressions ===
let score = 85
let grade = if score >= 90 then "A" else if score >= 80 then "B" else if score >= 70 then "C" else "F"
// @expect: B
print(grade)

// === If expression in function ===
fn abs_val(n: number): number
  if n < 0 then -n else n

// @expect: 5
print(abs_val(-5))
// @expect: 5
print(abs_val(5))

// === If expression as function argument ===
fn format(label: string, value: string): string
  label + ": " + value

let flag = true
// @expect: Status: enabled
print(format("Status", if flag then "enabled" else "disabled"))

// === If expression with complex conditions ===
let a = 10
let b = 20
let comparison = if a > b then "greater" else if a < b then "less" else "equal"
// @expect: less
print(comparison)

// === If expression with boolean result ===
let val = 7
let is_valid = if val > 0 and val < 10 then true else false
// @expect: true
print(is_valid)

// === If expression in list ===
let items = [1, 2, 3, 4, 5]
let mapped = map(items, (i) => if i % 2 == 0 then i * 2 else i)
// @expect: [1, 4, 3, 8, 5]
print(mapped)

// === If expression with null ===
fn safe_get(items: list[number], idx: number): number?
  if idx >= 0 and idx < len(items) then items[idx] else null

// @expect: 3
print(safe_get([1, 2, 3, 4, 5], 2) ?? 0)
// @expect: 0
print(safe_get([1, 2, 3, 4, 5], 10) ?? 0)

// === Chained if expressions ===
fn categorize(n: number): string
  if n < 0 then "negative" else if n == 0 then "zero" else if n < 10 then "small" else if n < 100 then "medium" else "large"

// @expect: negative
print(categorize(-5))
// @expect: zero
print(categorize(0))
// @expect: small
print(categorize(5))
// @expect: medium
print(categorize(50))
// @expect: large
print(categorize(500))

// === If expression with string concatenation ===
let name = "Alice"
let greeting = "Hello, " + if len(name) > 0 then name else "stranger"
// @expect: Hello, Alice
print(greeting)

// === If expression returning different computations ===
fn compute(mode: string, x: number): number
  if mode == "square" then x * x else if mode == "double" then x * 2 else x

// @expect: 25
print(compute("square", 5))
// @expect: 10
print(compute("double", 5))
// @expect: 5
print(compute("identity", 5))
