// @test: Recursion - Recursive Functions
import { slice, concat } from "std/collections"

// === Factorial ===
fn factorial(n: number): number
  if n <= 1 then return 1
  n * factorial(n - 1)

// @expect: 120
print(factorial(5))
// @expect: 1
print(factorial(0))

// === Fibonacci ===
fn fib(n: number): number
  if n <= 1 then return n
  fib(n - 1) + fib(n - 2)

// @expect: 0
print(fib(0))
// @expect: 1
print(fib(1))
// @expect: 55
print(fib(10))

// === Sum of list (recursive) ===
fn sum_list(items: list[number]): number
  if len(items) == 0 then return 0
  items[0] + sum_list(slice(items, 1, len(items)))

// @expect: 15
print(sum_list([1, 2, 3, 4, 5]))

// === Reverse list (recursive) ===
fn reverse_rec(items: list[number]): list[number]
  if len(items) <= 1 then return items
  let single: list[number] = [items[0]]
  let result: list[number] = concat(reverse_rec(slice(items, 1, len(items))), single)
  result

// @expect: [5, 4, 3, 2, 1]
print(reverse_rec([1, 2, 3, 4, 5]))

// === GCD (Euclidean) ===
fn gcd(a: number, b: number): number
  if b == 0 then return a
  gcd(b, a % b)

// @expect: 6
print(gcd(48, 18))
// @expect: 1
print(gcd(17, 5))

// === Power ===
fn power(base: number, exp: number): number
  if exp == 0 then return 1
  base * power(base, exp - 1)

// @expect: 8
print(power(2, 3))
// @expect: 243
print(power(3, 5))

// === Count down ===
fn count_down(n: number)
  if n <= 0 then return null
  print(n)
  count_down(n - 1)

// @expect: 3
// @expect: 2
// @expect: 1
count_down(3)

// === Mutual recursion ===
fn is_even(n: number): bool
  if n == 0 then return true
  is_odd(n - 1)

fn is_odd(n: number): bool
  if n == 0 then return false
  is_even(n - 1)

// @expect: true
print(is_even(4))
// @expect: false
print(is_even(5))
// @expect: true
print(is_odd(7))
