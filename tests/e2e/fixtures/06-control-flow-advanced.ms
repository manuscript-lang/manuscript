// @test: Control Flow - Advanced patterns

// === Nested loops ===
var total = 0
for i in 1..4
  for j in 1..4
    total = total + (i * j)
// @expect: 36
print(total)

// === Early return ===
fn find_index(items: list[string], target: string): number
  for i in 0..len(items)
    if items[i] == target then return i
  return -1

let items = ["a", "b", "c", "d"]
// @expect: 2
print(find_index(items, "c"))
// @expect: -1
print(find_index(items, "x"))

// === Continue to skip ===
fn get_odds(n: number): list[number]
  var result: list[number] = []
  for i in 1..(n + 1)
    if i % 2 == 0 then continue
    result.push(i)
  return result

// @expect: [1, 3, 5, 7, 9]
print(get_odds(10))

// === Break from loop ===
fn count_until(limit: number): number
  var count = 0
  for
    count = count + 1
    if count >= limit then break
  return count

// @expect: 5
print(count_until(5))

// === Complex if-else ===
fn describe(n: number): string
  if n < 0
    return "negative"
  else if n == 0
    return "zero"
  else if n < 10
    return "small"
  else
    return "big"

// @expect: small
print(describe(5))
// @expect: negative
print(describe(-3))
// @expect: big
print(describe(100))

// === Guard clauses ===
fn process(x: number?): string
  if x == null then return "no value"
  if x < 0 then return "invalid"
  return "valid: " + to_str(x)

// @expect: no value
print(process(null))
// @expect: invalid
print(process(-1))
// @expect: valid: 42
print(process(42))

// === Factorial with while-like loop ===
fn fact(n: number): number
  var result = 1
  var i = 2
  for
    if i > n then break
    result = result * i
    i = i + 1
  return result

// @expect: 5040
print(fact(7))

// === Prime check ===
fn is_prime(n: number): bool
  if n < 2 then return false
  for i in 2..n
    if n % i == 0 then return false
  return true

// @expect: false
print(is_prime(1))
// @expect: true
print(is_prime(7))
// @expect: false
print(is_prime(9))
