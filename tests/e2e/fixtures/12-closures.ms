// @test: Closures and Lexical Scope

// === Closure over parameter ===
fn make_adder(n)
  (x) => x + n

let add10 = make_adder(10)
let add5 = make_adder(5)
// @expect: 15
print(add10(5))
// @expect: 12
print(add5(7))

// === Closure over multiple variables ===
fn make_range_checker(low, high)
  (x) => x >= low and x <= high

let in_range = make_range_checker(1, 10)
// @expect: true
print(in_range(5))
// @expect: false
print(in_range(15))
// @expect: true
print(in_range(1))

// === Nested closure chain ===
fn make_adder_chain(a)
  (b) => (c) => a + b + c

let chain10 = make_adder_chain(10)
let chain10and20 = chain10(20)
// @expect: 36
print(chain10and20(6))

// === Closure in higher-order function ===
fn apply_twice(f, x)
  f(f(x))

let double = (n) => n * 2
// @expect: 20
print(apply_twice(double, 5))

// === Closure capturing loop variable ===
fn make_multipliers()
  var fns = []
  for i in 1..4
    let n = i
    fns.push((x) => x * n)
  fns

let mults = make_multipliers()
// @expect: 5
print(mults[0](5))
// @expect: 10
print(mults[1](5))
// @expect: 15
print(mults[2](5))

// === Closure with filter/map ===
fn filter_greater_than(items, threshold)
  filter(items, (x) => x > threshold)

let nums = [1, 5, 10, 15, 20]
// @expect: [10, 15, 20]
print(filter_greater_than(nums, 8))
// @expect: [15, 20]
print(filter_greater_than(nums, 12))
