// @test: Access Restriction Errors

// === Access type without instantiation ===
type Person
  name: string

let bad1 = Person.name
// @error: Cannot access properties on type

// === Access function properties ===
fn identity(x: number): number
  x

let fn_val = identity
let bad2 = fn_val.something
// @error: Cannot access properties on function

// === Index access on number ===
let num = 42
let bad3 = num[0]
// @error: Index access is not allowed

// === Reserved property name constructor ===
type BadType1
  constructor: string
// @error: reserved

// === Reserved property name __proto__ ===
type BadType2
  __proto__: string
// @error: reserved

// === Reserved property name toString ===
type BadType3
  toString: string
// @error: reserved

// === Reserved map key ===
let bad_map = {constructor: 1}
// @error: reserved
