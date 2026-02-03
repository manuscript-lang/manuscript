// @test: Pipe Operator - Function chaining with pipe

// === Basic pipe ===
let result = 5 | to_str
// @expect: 5
print(result)

// === Pipe chain ===
let text = "  HELLO  " | trim | lower
// @expect: hello
print(text)

// === Pipe with list operations ===
let nums = [1, 2, 3, 4, 5]
let doubled = nums | (x) => map(x, (n) => n * 2)
// @expect: [2, 4, 6, 8, 10]
print(doubled)

// === Multi-step pipe ===
fn add_one(n: number): number
  n + 1

fn double(n: number): number
  n * 2

fn square(n: number): number
  n * n

let val = 3 | add_one | double | square
// @expect: 64
print(val)

// === Pipe with string functions ===
let name = "alice" | upper
// @expect: ALICE
print(name)

// === Pipe with lambda ===
let x = 10 | (n) => n * 2 | (n) => n + 5
// @expect: 25
print(x)

// === Pipe preserves order ===
fn prepend(s: string): string
  "prefix_" + s

fn append(s: string): string
  s + "_suffix"

let str = "middle" | prepend | append
// @expect: prefix_middle_suffix
print(str)

// === Pipe with reduction ===
let numbers = [1, 2, 3, 4, 5]
let sum = numbers | (arr) => reduce(arr, 0, (a, b) => a + b)
// @expect: 15
print(sum)

// === Pipe in expression ===
fn process(input: number): number
  input | (n) => n * 2 | (n) => n + 10

// @expect: 30
print(process(10))

// === Pipe with filter and map ===
let items = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
let evens_doubled = items | (x) => filter(x, (n) => n % 2 == 0) | (x) => map(x, (n) => n * 2)
// @expect: [4, 8, 12, 16, 20]
print(evens_doubled)

// === Pipe with type conversion ===
let num = 42 | to_str | (s) => "The answer is " + s
// @expect: The answer is 42
print(num)

// === Nested pipe expressions ===
fn transform(n: number): number
  n | (x) => x + 1 | (x) => x * 2

// @expect: 22
print(transform(10))
// @expect: 12
print(transform(5))
