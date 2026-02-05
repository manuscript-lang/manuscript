// @test: Null Handling - Null assertion and checks

// === Null coalescing basic ===
let maybe_null: string? = null
// @expect: default
print(maybe_null ?? "default")

// === Null coalescing with value ===
let has_value: string? = "actual"
// @expect: actual
print(has_value ?? "default")

// === Null coalescing chain ===
let a: string? = null
let b: string? = null
let c: string? = "found"
// @expect: found
print(a ?? b ?? c ?? "none")

// === Null coalescing with numbers ===
let maybe_num: number? = null
// @expect: 42
print(maybe_num ?? 42)

let has_num: number? = 100
// @expect: 100
print(has_num ?? 42)

// === Null coalescing with zero ===
let zero: number? = 0
// @expect: 0
print(zero ?? 99)

// === Function returning nullable ===
fn find_item(items: list[string], target: string): string?
  for item in items
    if item == target then return item
  return null

let items = ["apple", "banana", "cherry"]
// @expect: banana
print(find_item(items, "banana") ?? "not found")
// @expect: not found
print(find_item(items, "grape") ?? "not found")

// === Null check in condition ===
fn process_optional(val: number?): string
  if val == null then return "no value"
  return "value: " + to_str(val)

// @expect: no value
print(process_optional(null))
// @expect: value: 42
print(process_optional(42))

// === Null with maps ===
fn get_config_value(config: map, key: string): string
  let val = config[key]
  val ?? "undefined"

let config = {host: "localhost", port: "8080"}
// @expect: localhost
print(get_config_value(config, "host"))
// @expect: undefined
print(get_config_value(config, "missing"))

// === Null in list operations ===
fn first_or_default(items: list[number], default_val: number): number
  if len(items) == 0 then return default_val
  items[0]

// @expect: 1
print(first_or_default([1, 2, 3], 0))
// @expect: 0
print(first_or_default([], 0))

// === Nested null coalescing ===
fn get_nested(obj: map): string
  let inner = obj["inner"]
  if inner == null then return "no inner"
  let value = inner?.["value"]
  value ?? "no value"

let nested = {inner: {value: "found"}}
// @expect: found
print(get_nested(nested))

let empty_nested = {other: "data"}
// @expect: no inner
print(get_nested(empty_nested))
