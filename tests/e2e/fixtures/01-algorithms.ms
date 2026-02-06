// @test: Algorithms - Sorting and Computation
import { floor } from "std/math"

// === Bubble Sort ===
fn bubble_sort(arr: list[number]): list[number]
  var result = clone(arr)
  var n = len(result)
  for i in 0..n
    for j in 0..(n - i - 1)
      if result[j] > result[j + 1]
        let temp = result[j]
        result[j] = result[j + 1]
        result[j + 1] = temp
  return result

let unsorted = [5, 2, 8, 1, 9]
// @expect: [1, 2, 5, 8, 9]
print(bubble_sort(unsorted))

// === Binary Search ===
fn binary_search(arr: list[number], target: number): bool
  var left = 0
  var right = len(arr) - 1
  for
    if left > right then return false
    let mid = floor((left + right) / 2)
    if arr[mid] == target then return true
    if arr[mid] < target
      left = mid + 1
    else
      right = mid - 1

let sorted = [1, 2, 3, 4, 5]
// @expect: true
print(binary_search(sorted, 3))
// @expect: false
print(binary_search(sorted, 10))

// === Factorial (iterative) ===
fn factorial(n: number): number
  var result = 1
  for i in 2..(n + 1)
    result = result * i
  return result

// @expect: 120
print(factorial(5))

// === Fibonacci Sequence ===
fn fib(count: number): list[number]
  var result: list[number] = []
  var a = 0
  var b = 1
  for _ in 0..count
    result.push(b)
    let temp = a + b
    a = b
    b = temp
  return result

// @expect: [1, 1, 2, 3, 5, 8]
print(fib(6))

// === Sum Range ===
fn sum_range(start: number, end: number): number
  var total = 0
  for i in start..(end + 1)
    total = total + i
  return total

// @expect: 55
print(sum_range(1, 10))

// === GCD ===
fn gcd(a: number, b: number): number
  var x = a
  var y = b
  for
    if y == 0 then return x
    let temp = y
    y = x % y
    x = temp

// @expect: 5
print(gcd(15, 25))
// @expect: 12
print(gcd(48, 36))
