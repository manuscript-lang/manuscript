// @test: Name and Index Rules - reserved member names and bracketed access

// === Member property cannot be named 'constructor' ===
type BadType
  constructor: string
// @error: constructor

// === Member property cannot be named '__proto__' ===
type BadProto
  __proto__: string
// @error: __proto__

// === Member property cannot be named 'prototype' ===
type BadPrototype
  prototype: string
// @error: prototype

// === Bracketed access on function not allowed ===
fn id(x: number): number
  x
let f = id
let _ = f["constructor"]
// @error: Index access is not allowed

// === Generic type args must be identifiers ===
type Box[T]
  value: T
let _ = Box["number"]
// @error: Generic type arguments

// === List index must be numeric ===
let nums = [1, 2, 3]
let _ = nums["0"]
// @error: List index
