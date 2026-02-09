// @test: Type System Soundness - Comprehensive assignability and type checking

// === Named Types Must Match Exactly ===

type Point
  x: number
  y: number

type Point3D
  x: number
  y: number
  z: number

// Named types must match exactly (no structural subtyping)
fn takes_point(p: Point): number
  p.x + p.y

let p3d = Point3D(1, 2, 3)
let bad_assign = takes_point(p3d)
// @error: not assignable

// === Generic Type Constraints ===

fn identity[T](x: T): T
  x

let num = identity(42)
let str_val = identity("hello")

// Generic with collections
fn first_elem[T](items: list[T]): T?
  items[0]

let nums = [1, 2, 3]
let first_num = first_elem(nums)

// === Union Type Assignability ===

type Success
  value: number

type MyError
  message: string

type MyResult = Success or MyError

fn make_success(): MyResult
  Success(42)

fn make_error(): MyResult
  MyError("failed")

// === Optional Type Handling ===

fn maybe_num(): number?
  42

let opt_num = maybe_num()
let forced: number = opt_num
// @error: not assignable

// Correct way
let safe: number = opt_num ?? 0

// Null to optional
let null_val: number? = null

// === Type Assertions ===

let any_val: unknown = 42
let num_val = if any_val is number then any_val else 0

let str_assert = "hello"
let bad_assert = str_assert as number
// @error: Type assertion 'as' is not allowed

// === Never Type Assignability ===

fn panic_fn(): never
  panic("error")

// Never is assignable to anything
fn returns_num(): number
  panic_fn()

// === Map Type Safety ===

let m: map[string, number] = {"a": 1}
let val = m["b"]

let bad_key = m[42]
// @error: not assignable
