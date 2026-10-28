import {expect_equal, expect_true, expect_false} from "@std/test.ms"
import {parse, JsonValue} from "@std/json.ms"

fn doc() JsonValue:
    let text = "\{\"user\":\{\"name\":\"ada\",\"age\":36,\"score\":1.5,\"big\":1e3,\"admin\":true,\"tags\":[\"a\",\"b\",\"c\"]\},\"none\":null\}"
    return parse(text).get()

fn user_field(d: JsonValue, key: String) Optional[JsonValue]:
    if let user = d.get("user"):
        if let field = user.get(key):
            return some(field.clone())
    return none

fn string_of(value: JsonValue) Optional[String]:
    if let text = value.as_string():
        return some(text.clone())

    return none

fn has_map(value: JsonValue) Bool:
    return value.as_map().is_some()

fn tag(d: JsonValue, index: Int) Optional[String]:
    if let tags = d.get("user"):
        if let list = tags.get("tags"):
            if let item = list.at(index):
                return string_of(item)
    return none

test "JSON accessors read nested objects without copying subtrees":
    let d = doc()
    try expect_equal(user_field(d, "name"), some(JsonValue.StringValue("ada")))
    try expect_equal(user_field(d, "name").and_then(fn n: string_of(n)), some("ada"))
    try expect_equal(user_field(d, "age").and_then(fn n: n.as_int()), some(36))
    try expect_equal(user_field(d, "admin").and_then(fn n: n.as_bool()), some(true))
    try expect_equal(user_field(d, "score").and_then(fn n: n.as_float()), some(1.5))
    try expect_equal(user_field(d, "age").and_then(fn n: n.as_float()), some(36.0))
    try expect_true(user_field(d, "missing").is_none())

test "JSON at indexes arrays from either end":
    let d = doc()
    try expect_equal(tag(d, 0), some("a"))
    try expect_equal(tag(d, -1), some("c"))
    try expect_equal(tag(d, -3), some("a"))
    try expect_true(tag(d, 3).is_none())
    try expect_true(tag(d, -4).is_none())

test "JSON borrowed list and map views match the tree":
    let d = doc()

    if let user = d.get("user"):
        if let tags = user.get("tags"):
            if let list = tags.as_list():
                try expect_equal(list.length(), 3)
        if let members = user.as_map():
            try expect_equal(members.length(), 6)

    try expect_true(d.as_map().is_some())

test "JSON accessors return none for the wrong type":
    let d = doc()
    try expect_true(d.get("missing").is_none())
    try expect_true(d.at(0).is_none())
    try expect_true(d.as_string().is_none())
    try expect_true(d.as_list().is_none())
    try expect_true(d.as_bool().is_none())
    try expect_true(user_field(d, "name").and_then(fn n: n.as_int()).is_none())
    try expect_true(user_field(d, "age").and_then(fn n: string_of(n)).is_none())
    try expect_true(user_field(d, "age").and_then(fn n: n.as_bool()).is_none())
    try expect_true(user_field(d, "name").and_then(fn n: n.as_float()).is_none())
    try expect_true(user_field(d, "tags").map(fn n: has_map(n)).get(true) == false)

test "JSON as_int rejects fractions exponents and overflow":
    let d = doc()
    try expect_true(user_field(d, "score").and_then(fn n: n.as_int()).is_none())
    try expect_true(user_field(d, "big").and_then(fn n: n.as_int()).is_none())
    try expect_equal(user_field(d, "big").and_then(fn n: n.as_float()), some(1000.0))

    let huge = try parse("99999999999999999999")
    try expect_true(huge.as_int().is_none())

    let neg = try parse("-7")
    try expect_equal(neg.as_int(), some(-7))

test "JSON is_null distinguishes null from absent and other values":
    let d = doc()
    if let value = d.get("none"):
        try expect_true(value.is_null())
    if let user = d.get("user"):
        try expect_false(user.is_null())
    try expect_true(d.get("missing").is_none())

# `get_in` lends the member it reaches, so a `ref` function can hand it back.
fn user_name(d: JsonValue) ref Optional[String]:
    if let name = d.get_in(["user", "name"]):
        return name.as_string()

    return none

test "JSON get_in reads a chain of members in place":
    let d = doc()
    try expect_equal(user_name(d), some("ada"))
    try expect_equal(d.get_in(["user", "age"]).and_then(fn n: n.as_int()), some(36))
    if let tags = d.get_in(["user", "tags"]):
        try expect_equal(tags.at(-1).and_then(fn t: string_of(t)), some("c"))
    try expect_true(d.get_in(["user", "missing"]).is_none())
    try expect_true(d.get_in(["user", "name", "first"]).is_none())
    try expect_true(d.get_in([]).is_none())
