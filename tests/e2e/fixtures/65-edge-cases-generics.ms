// @test: Generics Edge Cases - Comprehensive generic type testing
import { first, last, filter, map, reduce, find, take, drop, reverse, flatten, unique, contains, keys, values, sort } from "std/collections"

// === User-defined generic types ===
type Box[T]
  value: T
  fn get(): T
    value

let numBox = Box[number](42)
// @expect: 42
print(numBox.get())

let strBox = Box[string]("hello")
// @expect: hello
print(strBox.get())

// === Multi-type-param generic types ===
type Pair[A, B]
  first: A
  second: B

let pair = Pair[number, string](42, "answer")
// @expect: 42
print(pair.first)
// @expect: answer
print(pair.second)

type Triple[A, B, C]
  a: A
  b: B
  c: C

let triple = Triple[number, string, bool](1, "two", true)
// @expect: 1
print(triple.a)
// @expect: two
print(triple.b)
// @expect: true
print(triple.c)

// === Generic function type inference ===
fn identity[T](x: T): T
  x

// @expect: 123
print(identity(123))
// @expect: hello
print(identity("hello"))
// @expect: true
print(identity(true))

fn swap[A, B](a: A, b: B): list[unknown]
  [b, a]

let swapped = swap(1, "one")
// @expect: one
print(swapped[0])
// @expect: 1
print(swapped[1])

fn mapItems[T, U](items: list[T], f: fn(T): U): list[U]
  var result: list[U] = []
  for item in items
    result = [...result, f(item)]
  result

let tripled = mapItems([1, 2, 3], (x: number) => x * 3)
// @expect: 3
print(tripled[0])
// @expect: 9
print(tripled[2])

// === Multi-line map literals ===
let config = {
  "name": "test",
  "version": 1,
  "enabled": true
}
// @expect: test
print(config["name"])
// @expect: 1
print(config["version"])

// === Multi-line list literals ===
let items = [
  "first",
  "second",
  "third"
]
// @expect: 3
print(len(items))
// @expect: first
print(items[0])

// === Multi-line pipe expressions ===
let pipeResult = [1, 2, 3, 4, 5, 6]
| filter((x: number) => x % 2 == 0)
| map((x: number) => x * 10)
// @expect: 3
print(len(pipeResult))
// @expect: 20
print(pipeResult[0])
// @expect: 60
print(pipeResult[2])

// === Generic list type ===
let nums: list[number] = [1, 2, 3, 4, 5]
let strs: list[string] = ["a", "b", "c"]
let bools: list[bool] = [true, false, true]

// @expect: 5
print(len(nums))
// @expect: 3
print(len(strs))
// @expect: 3
print(len(bools))

// === Generic map type ===
let strMap: map[string, number] = {"a": 1, "b": 2, "c": 3}
let numMap: map[number, string] = {1: "one", 2: "two"}

// @expect: 1
print(strMap["a"])
// @expect: one
print(numMap[1])

// === Nested generic collections ===
let matrix: list[list[number]] = [[1, 2], [3, 4], [5, 6]]
var flatSum = 0
for row in matrix
  for cell in row
    flatSum = flatSum + cell
// @expect: 21
print(flatSum)

let nested: list[list[list[number]]] = [[[1, 2], [3]], [[4, 5, 6]]]
// @expect: 2
print(len(nested))
// @expect: 2
print(len(nested[0]))
// @expect: 3
print(len(nested[1][0]))

// === Map of lists ===
let mapOfLists: map[string, list[number]] = {"evens": [2, 4, 6], "odds": [1, 3, 5]}
// @expect: 3
print(len(mapOfLists["evens"] ?? []))
// @expect: 2
print(mapOfLists["evens"]?.[0] ?? 0)

// === List of maps ===
let users: list[map[string, string]] = [{"name": "Alice", "role": "admin"}, {"name": "Bob", "role": "user"}]
// @expect: Alice
print(users[0]["name"])
// @expect: user
print(users[1]["role"])

// === Stdlib first/last ===
// @expect: 1
print(first([1, 2, 3]) ?? 0)
// @expect: 3
print(last([1, 2, 3]) ?? 0)
// @expect: a
print(first(["a", "b", "c"]) ?? "none")
// @expect: c
print(last(["a", "b", "c"]) ?? "none")

// Empty list handling
// @expect: 0
print(first([]) ?? 0)
// @expect: 0
print(last([]) ?? 0)

// === Stdlib filter ===
let evens = filter([1, 2, 3, 4, 5, 6], (x: number) => x % 2 == 0)
// @expect: 3
print(len(evens))
// @expect: 2
print(evens[0])
// @expect: 4
print(evens[1])

let positives = filter([-2, -1, 0, 1, 2], (x: number) => x > 0)
// @expect: 2
print(len(positives))

// === Stdlib map ===
let doubled = map([1, 2, 3], (x: number) => x * 2)
// @expect: 2
print(doubled[0])
// @expect: 4
print(doubled[1])
// @expect: 6
print(doubled[2])

let lengths = map(["hi", "hello", "world"], (s) => len(s))
// @expect: 2
print(lengths[0])
// @expect: 5
print(lengths[1])
// @expect: 5
print(lengths[2])

// === Stdlib reduce ===
let sum = reduce([1, 2, 3, 4, 5], 0, (acc: number, x: number) => acc + x)
// @expect: 15
print(sum)

let product = reduce([1, 2, 3, 4], 1, (acc: number, x: number) => acc * x)
// @expect: 24
print(product)

let joined = reduce(["a", "b", "c"], "", (acc: string, x: string) => acc + x)
// @expect: abc
print(joined)

// Empty reduce
let empty: list[number] = []
let emptySum = reduce(empty, 100, (acc: number, x: number) => acc + x)
// @expect: 100
print(emptySum)

// === Stdlib find ===
let found = find([1, 2, 3, 4, 5], (x: number) => x > 3)
// @expect: 4
print(found ?? 0)

let notFound = find([1, 2, 3], (x: number) => x > 10)
// @expect: 0
print(notFound ?? 0)

// === Stdlib take/drop ===
let taken = take([1, 2, 3, 4, 5], 3)
// @expect: 3
print(len(taken))
// @expect: 1
print(taken[0])
// @expect: 3
print(taken[2])

let dropped = drop([1, 2, 3, 4, 5], 2)
// @expect: 3
print(len(dropped))
// @expect: 3
print(dropped[0])

// Edge cases
let takeMore = take([1, 2], 10)
// @expect: 2
print(len(takeMore))

let dropMore = drop([1, 2], 10)
// @expect: 0
print(len(dropMore))

// === Stdlib reverse ===
let reversed = reverse([1, 2, 3])
// @expect: 3
print(reversed[0])
// @expect: 1
print(reversed[2])

// === Stdlib flatten ===
let flat = flatten([[1, 2], [3], [4, 5, 6]])
// @expect: 6
print(len(flat))
// @expect: 1
print(flat[0])
// @expect: 6
print(flat[5])

// === Stdlib unique ===
let unique_nums = unique([1, 2, 2, 3, 3, 3])
// @expect: 3
print(len(unique_nums))

// === Stdlib contains ===
// @expect: true
print(contains([1, 2, 3], 2))
// @expect: false
print(contains([1, 2, 3], 5))
// @expect: true
print(contains(["a", "b", "c"], "b"))

// === Stdlib keys/values ===
let m = {"x": 1, "y": 2, "z": 3}
let ks = keys(m)
let vs = values(m)
// @expect: 3
print(len(ks))
// @expect: 3
print(len(vs))

// === Stdlib sort ===
let unsorted = [3, 1, 4, 1, 5, 9, 2, 6]
let sorted = sort(unsorted)
// @expect: 1
print(sorted[0])
// @expect: 1
print(sorted[1])
// @expect: 9
print(sorted[7])

// === Chained operations ===
let evensFiltered = filter([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], (x: number) => x % 2 == 0)
let squared = map(evensFiltered, (x: number) => x * x)
let chainResult = reduce(squared, 0, (acc: number, x: number) => acc + x)
// @expect: 220
print(chainResult)

// === Complex nested operations ===
let data = [[1, 2, 3], [4, 5], [6, 7, 8, 9]]
var sums: list[number] = []
for row in data
  sums = [...sums, reduce(row, 0, (acc: number, x: number) => acc + x)]
// @expect: 6
print(sums[0])
// @expect: 9
print(sums[1])
// @expect: 30
print(sums[2])
