// @test: Type Checks - Runtime type checking

// === typeof for primitives ===
// @expect: number
print(typeof(42))
// @expect: string
print(typeof("hello"))
// @expect: boolean
print(typeof(true))

// === typeof for collections ===
// @expect: list
print(typeof([1, 2, 3]))
// @expect: object
print(typeof({a: 1}))

// === typeof for null ===
// @expect: null
print(typeof(null))

// === Type-based branching ===
fn describe_type(val): string
  let t = typeof(val)
  match t
    "number" => "it's a number"
    "string" => "it's a string"
    "boolean" => "it's a boolean"
    _ => "it's something else"

// @expect: it's a number
print(describe_type(42))
// @expect: it's a string
print(describe_type("hello"))
// @expect: it's a boolean
print(describe_type(true))
// @expect: it's something else
print(describe_type([1, 2, 3]))

// === Check array type ===
fn is_list(val): bool
  typeof(val) == "list"

// @expect: true
print(is_list([1, 2, 3]))
// @expect: false
print(is_list({a: 1}))
// @expect: false
print(is_list(null))

// === Type-safe operations ===
fn safe_length(val): number
  let t = typeof(val)
  if t == "string" then return len(val)
  if t == "list" then return len(val)
  return 0

// @expect: 5
print(safe_length("hello"))
// @expect: 3
print(safe_length([1, 2, 3]))
// @expect: 0
print(safe_length(42))

// === Type in conditions ===
fn add_or_concat(a: unknown, b: unknown): string
  if typeof(a) == "string" or typeof(b) == "string"
    return to_str(a) + to_str(b)
  if typeof(a) == "number" and typeof(b) == "number"
    return to_str(a + b)
  return to_str(a) + to_str(b)

// @expect: hello world
print(add_or_concat("hello ", "world"))
// @expect: 15
print(add_or_concat(10, 5))
// @expect: 10five
print(add_or_concat(10, "five"))

// === Type with custom types ===
type Point
  x: number
  y: number

let p = Point(3, 4)
// @expect: Point
print(typeof(p))

// === Type check helper functions ===
fn is_number(val): bool
  typeof(val) == "number"

fn is_string(val): bool
  typeof(val) == "string"

fn is_bool(val): bool
  typeof(val) == "boolean"

// @expect: true
print(is_number(42))
// @expect: false
print(is_number("42"))
// @expect: true
print(is_string("hello"))
// @expect: true
print(is_bool(false))
