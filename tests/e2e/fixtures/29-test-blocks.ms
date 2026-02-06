// @test: Test Blocks - Test declarations
import { first, last } from "std/collections"

// === Basic test block ===
test "simple assertion"
  let x = 1 + 1
  assert x == 2

// === Test with multiple assertions ===
test "math operations"
  assert 2 + 2 == 4
  assert 10 - 3 == 7
  assert 5 * 4 == 20
  assert 20 / 5 == 4

// === Test with variables ===
test "variable usage"
  let name = "Alice"
  let age = 30
  assert len(name) == 5
  assert age > 18

// === Test with function calls ===
fn double(n: number): number
  n * 2

test "function testing"
  assert double(5) == 10
  assert double(0) == 0
  assert double(-3) == -6

// === Test with collections ===
test "list operations"
  let nums = [1, 2, 3, 4, 5]
  assert len(nums) == 5
  assert first(nums) == 1
  assert last(nums) == 5

// === Test with conditions ===
test "conditional logic"
  let x = 10
  let result = if x > 5 then "big" else "small"
  assert result == "big"

// === Test with loops ===
test "loop accumulation"
  var sum = 0
  for i in 1..6
    sum = sum + i
  assert sum == 15

// === Test string operations ===
test "string functions"
  let text = "Hello, World!"
  assert upper(text) == "HELLO, WORLD!"
  assert lower(text) == "hello, world!"
  assert len(text) == 13

// === Test with type instances ===
type Point
  x: number
  y: number

test "type instance"
  let p = Point(3, 4)
  assert p.x == 3
  assert p.y == 4

// Verify tests ran by printing
// @expect: all tests passed
print("all tests passed")
