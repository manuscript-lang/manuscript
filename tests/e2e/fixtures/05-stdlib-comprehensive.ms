// @test: Standard Library Functions

// === String operations ===
// @expect: 5
print(len("hello"))
// @expect: HELLO
print(upper("hello"))
// @expect: hello
print(lower("HELLO"))
// @expect: hi
print(trim("  hi  "))

let parts = split("a,b,c", ",")
// @expect: [a, b, c]
print(parts)
// @expect: a-b-c
print(join(parts, "-"))

// @expect: world
print(substring("hello world", 6, 11))

// === List operations ===
let nums = [1, 2, 3, 4, 5]
// @expect: 5
print(len(nums))
// @expect: 1
print(first(nums))
// @expect: 5
print(last(nums))

// @expect: [1, 2, 3]
print(take(nums, 3))
// @expect: [4, 5]
print(drop(nums, 3))

// @expect: [5, 4, 3, 2, 1]
print(reverse(nums))

let nested = [[1, 2], [3, 4]]
// @expect: [1, 2, 3, 4]
print(flatten(nested))

let dupes = [1, 2, 2, 3, 3, 3]
// @expect: [1, 2, 3]
print(unique(dupes))

// === Math functions ===
// @expect: 5
print(abs(-5))
// @expect: 2
print(min(2, 8))
// @expect: 8
print(max(2, 8))
// @expect: 5
print(clamp(10, 0, 5))
// @expect: 3
print(floor(3.7))
// @expect: 4
print(ceil(3.3))
// @expect: 4
print(round(3.6))

// === Type conversion ===
// @expect: 42
print(to_str(42))
// @expect: 3.14
print(to_num("3.14"))
// @expect: {"a":1}
print(to_json({a: 1}))

// === Contains check ===
// @expect: true
print(contains([1, 2, 3], 2))
// @expect: false
print(contains([1, 2, 3], 5))

// === Sort ===
let unsorted = [3, 1, 4, 1, 5]
// @expect: [1, 1, 3, 4, 5]
print(sort(unsorted))
