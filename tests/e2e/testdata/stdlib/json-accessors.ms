from "@std/testing.ms" import expect_equal, expect_true, expect_false
from "@std/json.ms" import parse, JsonValue

def doc() -> JsonValue:
    let text = "{\"user\":{\"name\":\"ada\",\"age\":36,\"score\":1.5,\"big\":1e3,\"admin\":true,\"tags\":[\"a\",\"b\",\"c\"]},\"none\":null}"
    return parse(text).get()

test "JSON accessors read nested objects and arrays by chaining":
    let d = doc()
    let name = (
        d
        .get("user")
        .and_then(lambda u: u.get("name"))
        .and_then(lambda n: n.as_string())
        .get("")
    )
    try expect_equal(name, "ada")
    try expect_equal(
        d.get("user").and_then(lambda u: u.get("age")).and_then(
            lambda n: n.as_int()
        ),
        some(36)
    )
    try expect_equal(
        d.get("user").and_then(lambda u: u.get("admin")).and_then(
            lambda n: n.as_bool()
        ),
        some(True)
    )
    try expect_equal(
        d.get("user").and_then(lambda u: u.get("score")).and_then(
            lambda n: n.as_float()
        ),
        some(1.5)
    )
    try expect_equal(
        d.get("user").and_then(lambda u: u.get("age")).and_then(
            lambda n: n.as_float()
        ),
        some(36.0)
    )

test "JSON at indexes arrays from either end":
    let tags = doc().get("user").and_then(lambda u: u.get("tags"))
    try expect_equal(
        tags.and_then(lambda t: t.at(0)).and_then(lambda v: v.as_string()), some("a")
    )
    try expect_equal(
        tags.and_then(lambda t: t.at(-1)).and_then(lambda v: v.as_string()), some("c")
    )
    try expect_equal(
        tags.and_then(lambda t: t.at(-3)).and_then(lambda v: v.as_string()), some("a")
    )
    try expect_true(tags.and_then(lambda t: t.at(3)).is_none())
    try expect_true(tags.and_then(lambda t: t.at(-4)).is_none())
    try expect_equal(
        tags.and_then(lambda t: t.as_list()).map(lambda l: l.length()), some(3)
    )

test "JSON accessors return none for the wrong type":
    let d = doc()
    let user = d.get("user")
    try expect_true(d.get("missing").is_none())
    try expect_true(d.at(0).is_none())
    try expect_true(d.as_string().is_none())
    try expect_true(d.as_list().is_none())
    try expect_true(d.as_map().is_some())
    try expect_true(
        user.and_then(lambda u: u.get("name")).and_then(
            lambda n: n.as_int()
        ).is_none()
    )
    try expect_true(
        user.and_then(lambda u: u.get("age")).and_then(
            lambda n: n.as_string()
        ).is_none()
    )
    try expect_true(
        user.and_then(lambda u: u.get("age")).and_then(
            lambda n: n.as_bool()
        ).is_none()
    )
    try expect_true(
        user.and_then(lambda u: u.get("tags")).and_then(
            lambda n: n.get("a")
        ).is_none()
    )
    try expect_true(
        user.and_then(lambda u: u.get("name")).and_then(
            lambda n: n.as_float()
        ).is_none()
    )

test "JSON as_int rejects fractions exponents and overflow":
    try expect_true(
        doc().get("user").and_then(lambda u: u.get("score")).and_then(
            lambda n: n.as_int()
        ).is_none()
    )
    try expect_true(
        doc().get("user").and_then(lambda u: u.get("big")).and_then(
            lambda n: n.as_int()
        ).is_none()
    )
    try expect_equal(
        doc().get("user").and_then(lambda u: u.get("big")).and_then(
            lambda n: n.as_float()
        ),
        some(1000.0)
    )

    let huge = try parse("99999999999999999999")
    try expect_true(huge.as_int().is_none())

    let neg = try parse("-7")
    try expect_equal(neg.as_int(), some(-7))

test "JSON is_null distinguishes null from absent and other values":
    let d = doc()
    try expect_true(d.get("none").map(lambda v: v.is_null()).get(False))
    try expect_false(d.get("user").map(lambda v: v.is_null()).get(True))
    try expect_true(d.get("missing").is_none())
