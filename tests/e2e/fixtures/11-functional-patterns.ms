// @test: Functional Patterns

// === Function composition ===
fn compose(f, g)
  (x) => f(g(x))

let add1 = (x) => x + 1
let double = (x) => x * 2

let add_then_double = compose(double, add1)
// @expect: 12
print(add_then_double(5))

// === Currying ===
fn curry_add(a)
  (b) => a + b

let add5 = curry_add(5)
// @expect: 8
print(add5(3))
// @expect: 15
print(add5(10))

// === Partial application ===
fn partial(f, first)
  (second) => f(first, second)

fn multiply(a, b)
  a * b

let triple = partial(multiply, 3)
// @expect: 15
print(triple(5))

// === Map with index ===
fn map_with_index(list, f)
  var result = []
  for i in 0..len(list)
    result.push(f(list[i], i))
  return result

let items = ["a", "b", "c"]
let indexed = map_with_index(items, (item, i) => to_str(i) + ":" + item)
// @expect: [0:a, 1:b, 2:c]
print(indexed)

// === Reduce with early exit ===
fn reduce_while(list, init, f, pred)
  var acc = init
  for item in list
    acc = f(acc, item)
    if pred(acc) then break
  return acc

let nums = [1, 2, 3, 4, 5, 6]
let sum_until_10 = reduce_while(nums, 0, (a, b) => a + b, (sum) => sum >= 10)
// @expect: 10
print(sum_until_10)

// === Predicate combinators ===
fn pred_and(p1, p2)
  (x) => p1(x) and p2(x)

fn pred_or(p1, p2)
  (x) => p1(x) or p2(x)

fn pred_not(p)
  (x) => not p(x)

let is_pos = (n) => n > 0
let is_even = (n) => n % 2 == 0
let is_pos_even = pred_and(is_pos, is_even)

// @expect: true
print(is_pos_even(4))
// @expect: false
print(is_pos_even(3))
// @expect: false
print(is_pos_even(-2))

// === Pipeline pattern ===
let data = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
let step1 = filter(data, (n) => n % 2 == 0)
let step2 = map(step1, (n) => n * 2)
let step3 = filter(step2, (n) => n > 10)
let result = reduce(step3, 0, (a, b) => a + b)
// @expect: 48
print(result)

// === Identity and constant ===
fn identity(x)
  x

fn constant(x)
  () => x

// @expect: 42
print(identity(42))

let always5 = constant(5)
// @expect: 5
print(always5())
// @expect: 5
print(always5())
