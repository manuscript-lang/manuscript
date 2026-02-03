// @test: Optionals - Nullable Types

// === Optional declaration ===
let maybe: string? = null
// @expect: null
print(maybe)

// === Optional with value ===
let has_val: string? = "hello"
// @expect: hello
print(has_val)

// === Null coalescing ===
// @expect: default
print(maybe ?? "default")
// @expect: hello
print(has_val ?? "default")

// === Optional in function ===
fn find_user(id: number): string?
  if id == 1 then return "Alice"
  if id == 2 then return "Bob"
  null

// @expect: Alice
print(find_user(1) ?? "not found")
// @expect: not found
print(find_user(99) ?? "not found")

// === Optional chaining pattern ===
fn get_length(s: string?): number
  if s == null then return 0
  len(s)

// @expect: 5
print(get_length("hello"))
// @expect: 0
print(get_length(null))

// === Optional in list ===
fn first_positive(nums: list[number]): number?
  for n in nums
    if n > 0 then return n
  null

// @expect: 3
print(first_positive([-1, -2, 3, 4]) ?? 0)
// @expect: 0
print(first_positive([-1, -2, -3]) ?? 0)

// === Multiple optionals ===
fn safe_divide(a: number, b: number): number?
  if b == 0 then return null
  a / b

let result = safe_divide(10, 2)
// @expect: 5
print(result ?? 0)

let bad_result = safe_divide(10, 0)
// @expect: 0
print(bad_result ?? 0)
