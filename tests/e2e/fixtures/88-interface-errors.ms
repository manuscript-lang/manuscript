// @test: Interface Errors - method body required, interface not constructible, embedding rules

// === Concrete type method must have a body ===
type Bad
  x: number
  fn get(): number
// @error: must have a body

// === Interface cannot be constructed ===
interface I
  fn m(): number

let x = I()
// @error: cannot be constructed

// === Cannot embed: interface not found ===
interface J
  NoSuchInterface
  fn m(): number
// @error: interface not found

// === Cannot embed: not an interface (embed type in interface) ===
type T
  x: number
interface K
  T
  fn m(): number
// @error: not an interface

// === Ambiguous access when two embedded interfaces define same method ===
interface A
  fn foo(): number
interface B
  fn foo(): number
interface Ambiguous
  A
  B
// @error: Ambiguous access
