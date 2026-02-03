// @test: Number Literals - Various number formats

// === Integer literals ===
// @expect: 42
print(42)
// @expect: 0
print(0)
// @expect: -17
print(-17)

// === Decimal literals ===
// @expect: 3.14
print(3.14)
// @expect: 0.5
print(0.5)
// @expect: -2.718
print(-2.718)

// === Large numbers ===
// @expect: 1000000
print(1000000)
// @expect: 999999999
print(999999999)

// === Scientific notation ===
// @expect: 1000
print(1e3)
// @expect: 0.001
print(1e-3)
// @expect: 1500000
print(1.5e6)

// === Number operations ===
let big = 1000000
let small = 0.001
// @expect: 1000000.001
print(big + small)

// === Number comparison ===
// @expect: true
print(3.14 > 3)
// @expect: true
print(0.1 + 0.2 > 0.29)

// === Number in expressions ===
fn calculate(base: number, exp: number): number
  base ^ exp

// @expect: 1000
print(calculate(10, 3))
// @expect: 1024
print(calculate(2, 10))

// === Number precision ===
let precise = 123.456789
// @expect: 123
print(floor(precise))
// @expect: 124
print(ceil(precise))
// @expect: 123
print(round(precise))

// === Number range ===
var sum_nums = 0
for i in 1..101
  sum_nums = sum_nums + i
// @expect: 5050
print(sum_nums)

// === Negative ranges ===
fn count_negatives(start: number, end_val: number): number
  var count = 0
  for i in start..end_val
    if i < 0
      count = count + 1
  count

// @expect: 5
print(count_negatives(-5, 5))
