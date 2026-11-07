import expect_equal from "@std/test/test.ms"

fn successful_value(value: Int) Int!:
    return ok(value)

fn consume(key: String, value: Int) Int:
    let keys = [key]
    return keys.length() + value

test "source consuming argument remains owned after later try":
    let key = "long-dynamic-map-key-{1}"
    try expect_equal(consume(key, try successful_value(7)), 8)

test "a function value consuming argument remains owned after later try":
    let key = "long-dynamic-map-key-{1}"
    let f = consume
    try expect_equal(f(key, try successful_value(7)), 8)

type OwnedBox:
    text: String

impl OwnedBox:
    fn consume(value: Int) Int:
        let boxes = [self]
        return boxes.length() + value

test "a source consuming receiver remains owned after later try":
    let box = OwnedBox("long-dynamic-map-key-{1}")
    try expect_equal(box.consume(try successful_value(7)), 8)

fn consume_reordered(value: Int, key: String) Int:
    let keys = [key]
    return keys.length() + value

test "held source arguments transfer by their declared slot":
    let key = "long-dynamic-map-key-{1}"
    try expect_equal(consume_reordered(key: key, value: try successful_value(7)), 8)

fn read(key: String, value: Int) Int:
    return key.length() + value

test "borrowing source calls preserve ordinary caller ownership":
    let key = "long-dynamic-map-key-{1}"
    try expect_equal(read(key, try successful_value(7)), key.length() + 7)
    try expect_equal(key, "long-dynamic-map-key-1")

fn select(key: String, value: Int) String:
    let _ignored = value
    return key

test "borrowed source results retain their captured argument":
    let key = "long-dynamic-map-key-{1}"
    let selected = select(key, try successful_value(7))
    try expect_equal(selected, "long-dynamic-map-key-1")

fn failed_value() Int!:
    return error(Error("expected failure"))

fn consumes_after_failure() Int!:
    let key = "long-dynamic-map-key-{1}"
    return ok(consume(key, try failed_value()))

test "a failing written try leaves held source arguments to cleanup":
    try expect_equal(consumes_after_failure().is_error(), true)

fn consume_with_default(
    key: String,
    value: Int,
    extra: Int = try successful_value(4)
) Int!:
    let keys = [key]
    return ok(keys.length() + value + extra)

fn fail_default(key: String, value: Int, extra: Int = try failed_value()) Int!:
    let keys = [key]
    return ok(keys.length() + value + extra)

test "held source arguments survive a successful default":
    let key = "long-dynamic-map-key-{1}"
    try expect_equal((try consume_with_default(key, try successful_value(7))), 12)

fn failing_default_call() Int!:
    let key = "long-dynamic-map-key-{1}"
    return fail_default(key, try successful_value(7))

test "a failing default retains held source argument cleanup":
    try expect_equal(failing_default_call().is_error(), true)

fn change_text(var text: String) Int:
    text = "long-dynamic-map-key-{2}"
    return text.length()

fn with_changing_default(
    var text: String, value: Int, changed: Int = change_text(var text)
) String:
    return "{text}:{value}:{changed}"

test "a default can replace an earlier var argument":
    var text = "long-dynamic-map-key-{1}"
    let result = with_changing_default(var text, try successful_value(7))
    try expect_equal(result, "long-dynamic-map-key-2:7:22")
    try expect_equal(text, "long-dynamic-map-key-2")

test "a temporary source receiver stays alive through later try":
    try expect_equal(
        OwnedBox("long-dynamic-map-key-{1}").consume(try successful_value(7)), 8
    )
