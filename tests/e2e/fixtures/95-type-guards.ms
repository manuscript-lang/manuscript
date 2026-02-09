// @test: Type Guards - Guards for types, generic types, and generic functions

// === Guard for concrete types ===
fn is_string_guard(x: unknown): x is string
  typeof(x) == "string"

fn is_number_guard(x: unknown): x is number
  typeof(x) == "number"

fn is_list_of_numbers_guard(x: unknown): x is list[number]
  typeof(x) == "list"

fn is_map_guard(x: unknown): x is map
  typeof(x) == "object"

fn use_string_guard(raw: unknown): string
  if is_string_guard(raw)
    "str:" + raw
  else
    "not-str"

fn use_number_guard(raw: unknown): number
  if is_number_guard(raw)
    raw + 1
  else
    0

// @expect: str:hello
print(use_string_guard("hello"))
// @expect: not-str
print(use_string_guard(42))
// @expect: 43
print(use_number_guard(42))
// @expect: 0
print(use_number_guard("x"))

// === Guard for list[number] - concrete ===
fn sum_if_numbers_list(raw: unknown): number
  if is_list_of_numbers_guard(raw)
    var s = 0
    for n in raw
      s = s + n
    s
  else
    0

// @expect: 6
print(sum_if_numbers_list([1, 2, 3]))
// @expect: 0
print(sum_if_numbers_list("not a list"))

// === Guard for map ===
fn get_name_from_map(raw: unknown): string
  if is_map_guard(raw)
    let n = raw["name"]
    if n is string then n else "?"
  else
    "not-map"

// @expect: Alice
print(get_name_from_map({name: "Alice", age: 30}))
// @expect: not-map
print(get_name_from_map(42))

// === Generic type guard: x is list[T] ===
fn is_list_of[T](x: unknown): x is list[T]
  typeof(x) == "list"

// Use generic guard with explicit type arg at call site (non-generic caller)
fn sum_if_list_of_numbers(raw: unknown): number
  if is_list_of[number](raw)
    var s = 0
    for n in raw
      s = s + n
    s
  else
    0

// @expect: 6
print(sum_if_list_of_numbers([1, 2, 3]))
// @expect: 0
print(sum_if_list_of_numbers("skip"))

// Same generic guard with string: x is list[string]
fn join_if_list_of_strings(raw: unknown): string
  if is_list_of[string](raw)
    var s = ""
    for w in raw
      s = s + w
    s
  else
    "not-list"

// @expect: ab
print(join_if_list_of_strings(["a", "b"]))
// @expect: not-list
print(join_if_list_of_strings(99))

// === Guard for object type (named type) ===
type Point
  x: number
  y: number

fn is_point_guard(x: unknown): x is Point
  typeof(x) == "Point"

fn point_sum(raw: unknown): number
  if is_point_guard(raw)
    raw.x + raw.y
  else
    0

let pt = Point(3, 4)
// @expect: 7
print(point_sum(pt))
// @expect: 0
print(point_sum(42))

// === Generic user type: Box[number] vs Box[string] (runtime __typeArgs) ===
type Box[T]
  value: T

fn is_box_number(x: unknown): x is Box[number]
  x is Box[number]

fn is_box_string(x: unknown): x is Box[string]
  x is Box[string]

let numBox = Box[number](42)
let strBox = Box[string]("hello")
// @expect: true
print(is_box_number(numBox))
// @expect: false
print(is_box_number(strBox))
// @expect: false
print(is_box_string(numBox))
// @expect: true
print(is_box_string(strBox))
