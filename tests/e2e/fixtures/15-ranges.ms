// @test: Ranges - Iteration Patterns

// === Basic range ===
var sum = 0
for i in 0..5
  sum = sum + i
// @expect: 10
print(sum)

// === Range in list ===
var items = []
for i in 1..4
  items.push(i * 10)
// @expect: [10, 20, 30]
print(items)

// === Nested ranges ===
var pairs = []
for i in 1..3
  for j in 1..3
    pairs.push(to_str(i) + "," + to_str(j))
// @expect: [1,1, 1,2, 2,1, 2,2]
print(pairs)

// === Range with condition ===
var evens = []
for i in 0..10
  if i % 2 == 0
    evens.push(i)
// @expect: [0, 2, 4, 6, 8]
print(evens)

// === Range with break ===
var found = -1
for i in 0..100
  if i * i > 50
    found = i
    break
// @expect: 8
print(found)

// === Range with continue ===
var odds = []
for i in 0..10
  if i % 2 == 0 then continue
  odds.push(i)
// @expect: [1, 3, 5, 7, 9]
print(odds)

// === Range calculation ===
fn sum_range(start: number, end_val: number): number
  var total = 0
  for i in start..end_val
    total = total + i
  total

// @expect: 45
print(sum_range(0, 10))
// @expect: 35
print(sum_range(5, 10))

// === Range with negative ===
fn countdown(n: number)
  var count = n
  for i in 0..n
    print(count)
    count = count - 1

// @expect: 3
// @expect: 2
// @expect: 1
countdown(3)

// === Range length pattern ===
let words = ["one", "two", "three"]
for i in 0..len(words)
  print(words[i])
// @expect: one
// @expect: two
// @expect: three
