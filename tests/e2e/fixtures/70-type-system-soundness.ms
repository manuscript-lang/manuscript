// @test: Type System Soundness - Comprehensive assignability and type checking

// === Structural Subtyping for Objects ===

type Point
  x: number
  y: number

type Point3D
  x: number
  y: number
  z: number

// Named types must match exactly
fn takes_point(p: Point): number
  p.x + p.y

let p3d = Point3D(1, 2, 3)
let bad_assign = takes_point(p3d)
// @error: not assignable

// === Function Type Variance ===

type Animal
  name: string

type Dog extends Animal
  breed: string
  fn init(name: string, breed: string)
    super(name)
    breed = breed

fn process_animal(handler: fn(Animal): void): void
  handler(Animal("generic"))

fn dog_handler(d: Dog): void
  print(d.breed)

// Should error: dog_handler expects Dog, but will receive Animal
let bad_fn = process_animal(dog_handler)
// @error: not assignable

// Covariant return: can return narrower type
fn get_animal(): Animal
  Dog("Rex", "Labrador")

// === Generic Type Constraints ===

fn identity[T](x: T): T
  x

let num = identity(42)
let str = identity("hello")

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

// === List Invariance ===

type Cat extends Animal
  whiskers: number

let dogs: list[Dog] = [Dog("Rex", "Lab")]
let animals: list[Animal] = dogs
// @error: not assignable

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

let any_val: any = 42
let num_val = any_val as number

let str_val = "hello"
let bad_assert = str_val as number
// @error: Cannot assert

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
