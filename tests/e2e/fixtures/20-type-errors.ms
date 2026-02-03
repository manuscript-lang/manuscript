// @test: Type Errors - Compilation Errors

// === Type mismatch in assignment ===
let x: number = "hello"
// @error: not assignable

// === Immutability violation ===
let y = 10
y = 20
// @error: Cannot assign to immutable

// === Undefined variable ===
let result = undefined_var + 1
// @error: Unknown identifier

// === Variable redefinition ===
let z = 10
let z = 20
// @error: already defined

// === Unknown function ===
let val = unknown_function(5)
// @error: Unknown identifier

// === Boolean type mismatch ===
let b: bool = 42
// @error: not assignable

// === Too few function arguments ===
fn add(a: number, b: number): number
  a + b
let sum = add(1)
// @error: Expected at least 2

// === Wrong function argument type ===
fn greet(name: string): string
  "Hello " + name
let msg = greet(42)
// @error: not assignable

// === Arithmetic on non-numbers ===
let bad_math = "hello" - 5
// @error: requires number

// === String multiplication fails ===
let bad_mult = "x" * 3
// @error: requires number

// === List index with string fails ===
let nums = [1, 2, 3]
let bad_idx = nums["a"]
// @error: not assignable to 'number'

// === Missing property on type ===
type User
  name: string
let u = User("Alice")
let age = u.age
// @error: does not exist

// === Return outside function ===
return 42
// @error: outside of function

// === Break outside loop ===
break
// @error: outside of loop

// === Continue outside loop ===
continue
// @error: outside of loop
