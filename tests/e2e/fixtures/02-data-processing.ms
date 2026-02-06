// @test: Data Processing - Transformations

// === Filter and reduce ===
let nums = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
let evens = filter(nums, (n) => n % 2 == 0)
// @expect: [2, 4, 6, 8, 10]
print(evens)

let sum = reduce(nums, 0, (acc, n) => acc + n)
// @expect: 55
print(sum)

// === Map transformation ===
let words = ["hello", "world"]
let upper_words = map(words, (w) => upper(w))
// @expect: [HELLO, WORLD]
print(upper_words)

// === Chained operations ===
let data = [1, 2, 3, 4, 5]
let doubled = map(data, (x) => x * 2)
let big = filter(doubled, (x) => x > 5)
let total = reduce(big, 0, (a, b) => a + b)
// @expect: 24
print(total)

// === Group counting ===
fn count_evens_odds(items: list[number])
  var evens = 0
  var odds = 0
  for n in items
    if n % 2 == 0
      evens = evens + 1
    else
      odds = odds + 1
  {evens: evens, odds: odds}

// @expect: {evens: 5, odds: 5}
print(count_evens_odds(nums))

// === Object processing ===
let users = [{name: "Alice", age: 30}, {name: "Bob", age: 25}]

let names = map(users, (u: map[string, string or number]) => u["name"] as string)
// @expect: [Alice, Bob]
print(names)

let ages = map(users, (u: map[string, string or number]) => u["age"] as number)
let total_age = reduce(ages, 0, (a: number, b: number) => a + b)
// @expect: 55
print(total_age)

// === Find element ===
let found = find(users, (u: map[string, string or number]) => (u["name"] as string) == "Bob")
// @expect: {name: Bob, age: 25}
print(found)

// === Any/All predicates ===
let any_adult = any(ages, (a: number) => a >= 18)
// @expect: true
print(any_adult)

let all_adult = all(ages, (a: number) => a >= 18)
// @expect: true
print(all_adult)
