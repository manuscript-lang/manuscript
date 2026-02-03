// @test: Extended Type Errors - Comprehensive Type Checking

// === Function already defined ===
fn duplicate(): number
  1
fn duplicate(): number
  2
// @error: already defined

// === Type already defined ===
type MyType
  x: number
type MyType
  y: string
// @error: already defined

// === Return type mismatch ===
fn returns_number(): number
  "oops"
// @error: not assignable

// === Return missing value ===
fn needs_value(): number
  return
// @error: must have a value

// === Map index type mismatch ===
let m: map[string, number] = {"a": 1}
let v = m[123]
// @error: not assignable to 'string'

// === Unknown named parameter ===
fn greet(name: string): string
  "Hello " + name
let msg = greet(unknown_param: "Alice")
// @error: Unknown parameter

// === Too many arguments ===
fn one_arg(x: number): number
  x * 2
let over = one_arg(1, 2, 3)
// @error: Expected

// === Type check with invalid type ===
let val = 5
if val is UndefinedType
  print("never")
// @error: Unknown

// === Union type property access without narrowing ===
type A
  x: number
type B  
  y: string
type AB = A or B
fn get_ab(): AB
  A(1)
let ab = get_ab()
let invalid = ab.x
// @error: does not exist

// === Division type check ===
let div_bad = "hello" / 2
// @error: requires number

// === Modulo type check ===
let mod_bad = "hello" % 2
// @error: requires number

// === Exponent type check ===
let exp_bad = "hello" ^ 2
// @error: requires number

// === Unary minus on string ===
let neg_bad = -"hello"
// @error: requires number

// === List element type mismatch ===
let mixed: list[number] = [1, "two", 3]
// @error: not assignable

// === Map value type mismatch ===
let map_bad: map[string, number] = {"a": "one"}
// @error: not assignable

// === Function return type mismatch ===
fn outer(): number
  fn inner(): string
    return 42
  0
// @error: not assignable

// === Property access on primitive ===
let prim = 42
let prop_bad = prim.nonexistent
// @error: does not exist
