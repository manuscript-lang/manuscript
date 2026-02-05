// Test: Access restrictions for safety
// These tests verify type-level restrictions

type Person
  name: string
  age: number

// ERROR: Cannot access properties on type directly
// let x = Person.name

test "type must be instantiated to access properties"
  let p = Person("Alice", 30)
  assert p.name == "Alice"

test "list index must be numeric"
  let arr = [1, 2, 3]
  assert arr[0] == 1
  assert arr[1] == 2

test "string index must be numeric"
  let s = "hello"
  assert s[0] == "h"

test "map index can be any compatible type"
  let m = {a: 1}
  assert m["a"] == 1

// ERROR tests would be:
// let arr = [1, 2, 3]
// let x = arr["invalid"]  // Error: List index must be number

// let fn_val = (x: number) => x + 1
// let y = fn_val.something  // Error: Cannot access properties on function

type Container[T]
  value: T

test "generic types require identifier type args"
  let c = Container[number](42)
  assert c.value == 42
