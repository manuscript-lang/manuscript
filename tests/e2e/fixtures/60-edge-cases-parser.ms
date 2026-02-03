// @test: Parser Edge Cases - Unusual but valid syntax

// === Deeply nested member access ===
type A
  b: B
type B
  c: C
type C
  d: D
type D
  e: E
type E
  value: number
let deep = A(B(C(D(E(42)))))
// @expect: 42
print(deep.b.c.d.e.value)

// === Deeply nested function calls ===
fn add1(n: number): number
  n + 1
fn double(n: number): number
  n * 2
fn square(n: number): number
  n * n
// @expect: 36
print(square(double(add1(add1(add1(0))))))

// === Chained pipe operators ===
fn inc(n: number): number
  n + 1
fn dec(n: number): number
  n - 1
let piped = 5 | inc | inc | inc | dec | double
// @expect: 14
print(piped)

// === Complex operator precedence ===
// @expect: 17
print(2 + 3 * 5)
// @expect: 25
print((2 + 3) * 5)
// @expect: 512
print(2 ^ 3 ^ 2)
// @expect: 64
print((2 ^ 3) ^ 2)

// === Null coalescing chain ===
let opt_a: number? = null
let opt_b: number? = null  
let opt_c: number? = 10
let coalesced = opt_a ?? opt_b ?? opt_c ?? 0
// @expect: 10
print(coalesced)

// === Nested ternary-like if expressions ===
fn classify(n: number): string
  if n < 0 then "negative" else if n == 0 then "zero" else "positive"
// @expect: negative
print(classify(-5))
// @expect: zero
print(classify(0))
// @expect: positive
print(classify(5))

// === Complex destructuring ===
type Point
  x: number
  y: number
type Line
  start: Point
  end: Point
let line = Line(Point(0, 0), Point(10, 20))
let {start, end} = line
// @expect: 0
print(start.x)
// @expect: 20
print(end.y)

// === Array destructuring with rest ===
let nums = [1, 2, 3, 4, 5]
let [head, second, ...tail] = nums
// @expect: 1
print(head)
// @expect: 2
print(second)
// @expect: 3
print(len(tail))

// === Lambda in various positions ===
let funcs = [(x: number) => x + 1, (x: number) => x * 2, (x: number) => x - 1]
var running = 10
for f in funcs
  running = f(running)
// @expect: 21
print(running)

// === Inline if in various contexts ===
fn my_abs(n: number): number
  if n < 0 then -n else n
let items = [1, -2, 3, -4]
var sum = 0
for x in items
  sum = sum + (if x > 0 then x else -x)
// @expect: 10
print(sum)

// === Spread in list literal ===
let base = [1, 2, 3]
let extended = [0, ...base, 4, 5]
// @expect: 6
print(len(extended))
// @expect: 0
print(extended[0])
// @expect: 5
print(extended[5])

// === Spread in map literal ===
let base_map = {"a": 1, "b": 2}
let extended_map = {...base_map, "c": 3}
// @expect: 1
print(extended_map["a"])
// @expect: 3
print(extended_map["c"])

// === String template with expressions ===
let name = "world"
let count = 3
// @expect: Hello, world! Count: 3
print("Hello, {name}! Count: {count}")

// === Complex range expressions ===
var range_sum = 0
for i in 1..6
  range_sum = range_sum + i
// @expect: 15
print(range_sum)

// === Slice syntax variations ===
let arr = [0, 1, 2, 3, 4, 5]
// @expect: 3
print(len(arr[1:4]))
// @expect: 3
print(len(arr[3:]))
// @expect: 3
print(len(arr[:3]))
