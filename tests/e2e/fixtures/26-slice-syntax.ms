// @test: Slice Syntax - Array and string slicing

// === Basic slice with builtins ===
let nums = [1, 2, 3, 4, 5]
// @expect: [2, 3, 4]
print(slice(nums, 1, 4))

// === Slice from start ===
// @expect: [1, 2, 3]
print(slice(nums, 0, 3))

// === Slice to end ===
// @expect: [3, 4, 5]
print(slice(nums, 2, 5))

// === Slice single element range ===
// @expect: [3]
print(slice(nums, 2, 3))

// === Take and drop ===
// @expect: [1, 2]
print(take(nums, 2))
// @expect: [4, 5]
print(drop(nums, 3))

// === String slicing ===
let text = "Hello, World!"
// @expect: Hello
print(substring(text, 0, 5))
// @expect: World
print(substring(text, 7, 12))

// === Combine take and drop ===
let items = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
let middle = drop(take(items, 7), 3)
// @expect: [4, 5, 6, 7]
print(middle)

// === Slice in function ===
fn get_range(arr: list[number], start: number, end_val: number): list[number]
  slice(arr, start, end_val)

// @expect: [3, 4, 5]
print(get_range(nums, 2, 5))

// === Slice empty result ===
let empty_slice = slice(nums, 2, 2)
// @expect: []
print(empty_slice)

// === Nested slicing ===
let matrix = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
let row = matrix[1]
// @expect: [5, 6]
print(slice(row, 1, 3))

// === Slice with variables ===
let start_idx = 1
let end_idx = 4
// @expect: [2, 3, 4]
print(slice(nums, start_idx, end_idx))

// === Slice preserves type ===
let strings = ["a", "b", "c", "d", "e"]
let sliced_strings = slice(strings, 1, 4)
// @expect: [b, c, d]
print(sliced_strings)
// @expect: b
print(sliced_strings[0])
