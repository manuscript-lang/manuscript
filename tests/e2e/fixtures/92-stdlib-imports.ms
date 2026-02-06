// @test: Stdlib Imports - importing from std/math, std/collections, std/concurrency

import { sqrt, pow, floor, ceil, round, abs, min, max, clamp } from "std/math"
import { sort, keys, values, entries, first, last, take, drop, reverse, contains, unique, flatten, zip, concat, range, slice, map, each, filter, reduce, find, any, all, group_by, sort_by } from "std/collections"
import { race, sleep, delay } from "std/concurrency"

// === std/math ===
// @expect: 4
print(sqrt(16))
// @expect: 8
print(pow(2, 3))
// @expect: 3
print(floor(3.7))
// @expect: 4
print(ceil(3.2))
// @expect: 4
print(round(3.5))
// @expect: 5
print(abs(-5))
// @expect: 1
print(min(1, 2))
// @expect: 2
print(max(1, 2))
// @expect: 5
print(clamp(10, 0, 5))

// === std/collections - extern ===
let nums = [3, 1, 2]
// @expect: [1, 2, 3]
print(sort(nums))

let m = { a: 1, b: 2 }
// @expect: [a, b]
print(keys(m))
// @expect: [1, 2]
print(values(m))

// === std/collections - pure ===
// @expect: 1
print(first([1, 2, 3]))
// @expect: 3
print(last([1, 2, 3]))
// @expect: [1, 2]
print(take([1, 2, 3, 4], 2))
// @expect: [3, 4]
print(drop([1, 2, 3, 4], 2))
// @expect: [3, 2, 1]
print(reverse([1, 2, 3]))
// @expect: true
print(contains([1, 2, 3], 2))
// @expect: false
print(contains([1, 2, 3], 4))
// @expect: [1, 2, 3]
print(unique([1, 2, 2, 3, 3]))
// @expect: [1, 2, 3, 4]
print(flatten([[1, 2], [3, 4]]))
// @expect: [1, 2, 3, 4, 5, 6]
print(concat([1, 2], [3, 4], [5, 6]))
// @expect: [0, 1, 2, 3, 4]
print(range(0, 5))
// @expect: [2, 3]
print(slice([1, 2, 3, 4], 1, 3))
// @expect: [2, 4, 6]
print(map([1, 2, 3], (x) => x * 2))
// @expect: [2, 4]
print(filter([1, 2, 3, 4], (x) => x % 2 == 0))
// @expect: 10
print(reduce([1, 2, 3, 4], 0, (acc, x) => acc + x))
// @expect: 3
print(find([1, 2, 3, 4], (x) => x > 2))
// @expect: true
print(any([1, 2, 3], (x) => x > 2))
// @expect: false
print(all([1, 2, 3], (x) => x > 2))

// === std/concurrency - race with spawn ===
fn work(): number
  42

fn race_test()
  let a = spawn work()
  let b = spawn work()
  let result = race([a, b])
  // @expect: 42
  print(result)
race_test()
