import expect_equal from "@std/test/test.ms"

fn identity(s: String) String:
    return s

fn apply(f: fn(String) String, s: String) String:
    return f(s)

test "borrowed string callback":
    let s = "hello"
    let out = apply(identity, s)
    try expect_equal(out, "hello")

fn generic[T](value: T) T:
    return value

fn pick(items: List[String]) String:
    return items[0]

test "generic and list-field callback results outlive arguments":
    let generic_string: fn(String) String = generic[String]
    let first = generic_string("dynamic-{42}")
    let picker = pick
    let second = picker(["dynamic-{17}"])
    try expect_equal(first, "dynamic-42")
    try expect_equal(second, "dynamic-17")

fn default_identity(value: String, _tag: Int = 0) String:
    return value

test "defaulted source callback preserves borrowed strings":
    let f = default_identity
    let first = f("default-{1}")
    let second = f("explicit-{2}", 3)
    try expect_equal(first, "default-1")
    try expect_equal(second, "explicit-2")

fn list_identity(items: List[String]) List[String]:
    return items

test "borrowed list callback returns independent data":
    let f = list_identity
    let first = f(["a-{1}", "b-{2}"])
    let second = f(["c-{3}"])
    try expect_equal(first, ["a-1", "b-2"])
    try expect_equal(second, ["c-3"])
