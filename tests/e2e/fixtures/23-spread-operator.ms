// @test: Spread Operator - Spreading lists and maps

// === Spread in list literal ===
let a = [1, 2, 3]
let b = [4, 5, 6]
let combined = [...a, ...b]
// @expect: [1, 2, 3, 4, 5, 6]
print(combined)

// === Spread with additional elements ===
let base = [2, 3, 4]
let extended = [1, ...base, 5]
// @expect: [1, 2, 3, 4, 5]
print(extended)

// === Spread to copy list ===
let original = [1, 2, 3]
var copy = [...original]
copy.push(4)
// @expect: [1, 2, 3]
print(original)
// @expect: [1, 2, 3, 4]
print(copy)

// === Multiple spreads ===
let arr_x = [1, 2]
let arr_y = [3, 4]
let arr_z = [5, 6]
let all_combined = [...arr_x, ...arr_y, ...arr_z]
// @expect: [1, 2, 3, 4, 5, 6]
print(all_combined)

// === Spread in function call context ===
fn process_all(items: list[number]): number
  reduce(items, 0, (acc: number, n: number) => acc + n)

let nums = [1, 2, 3, 4, 5]
// @expect: 15
print(process_all(nums))

// === Spread with empty list ===
let empty: list[number] = []
let with_empty = [...empty, 1, 2, 3]
// @expect: [1, 2, 3]
print(with_empty)

// === Nested spread ===
let inner1 = [1, 2]
let inner2 = [3, 4]
let outer = [[...inner1], [...inner2]]
// @expect: [[1, 2], [3, 4]]
print(outer)

// === Spread in map literal ===
let defaults = {color: "blue", size: "medium"}
let custom = {...defaults, color: "red"}
// @expect: red
print(custom.color)
// @expect: medium
print(custom.size)

// === Merge maps with spread ===
let map1 = {a: 1, b: 2}
let map2 = {c: 3, d: 4}
let merged = {...map1, ...map2}
// @expect: [a, b, c, d]
print(keys(merged))
// @expect: [1, 2, 3, 4]
print(values(merged))

// === Override with spread ===
let base_config = {host: "localhost", port: 8080, debug: false}
let dev_config = {...base_config, debug: true, port: 3000}
// @expect: localhost
print(dev_config.host)
// @expect: 3000
print(dev_config.port)
// @expect: true
print(dev_config.debug)

// === Spread string characters ===
let chars = split("hello", "")
// @expect: 5
print(len(chars))
// @expect: h
print(chars[0])
