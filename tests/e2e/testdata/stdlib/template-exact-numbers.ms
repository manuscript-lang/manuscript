import (
    compile from "@std/text/template.ms",
    parse, JsonValue from "@std/data/json.ms",
    expect_equal from "@std/test/test.ms",
)

fn check(expression: String, data: String, expected: String) Unit!:
    let template = try compile(
        "\{\{ if {expression} \}\}yes\{\{ else \}\}no\{\{ end \}\}"
    )
    try expect_equal((try template.render(try parse(data))), expected)
    return ok(unit)

test "underflow is not zero":
    try check("value", "\{\"value\":1e-400\}", "yes")

test "underflow does not equal zero":
    try check("left == right", "\{\"left\":1e-400,\"right\":0\}", "no")

test "underflow orders above zero":
    try check("left > right", "\{\"left\":1e-400,\"right\":0\}", "yes")

test "large integer neighbors are distinct":
    try check(
        "left == right", "\{\"left\":9007199254740992,\"right\":9007199254740993\}",
        "no"
    )

test "large integer neighbors retain order":
    try check(
        "left < right", "\{\"left\":9007199254740992,\"right\":9007199254740993\}",
        "yes"
    )

test "overflow values retain order":
    try check("left < right", "\{\"left\":1e400,\"right\":2e400\}", "yes")

test "equivalent overflow numbers compare equal":
    try check("left == right", "\{\"left\":1e400,\"right\":10e399\}", "yes")

test "ordinary numbers retain ordering":
    try check("left < right", "\{\"left\":1,\"right\":2\}", "yes")

test "equivalent ordinary numbers compare equal":
    try check("left == right", "\{\"left\":1,\"right\":1.0\}", "yes")

test "signed zero remains false":
    try check("value", "\{\"value\":-0.00e-400\}", "no")

test "decimal coefficient and exponent normalizations agree":
    let pairs = [
        ["1e99", "10e98"],
        ["1e-99", "0.1e-98"],
        ["1e0", "0.01e2"],
        ["-1.2300e+00002", "-123"],
        [
            "1e999999999999999999999999999999", "10e999999999999999999999999999998"
        ],
        [
            "1e-999999999999999999999999999999", "0.1e-999999999999999999999999999998"
        ]
    ]

    for pair in pairs:
        let values = "\{\"left\":{pair[0]},\"right\":{pair[1]}\}"
        try check("left == right and left <= right and left >= right", values, "yes")
        try check("left != right or left < right or left > right", values, "no")

test "coefficient suffixes and negative values preserve order":
    let pairs = [
        ["1.001", "1.01"], ["-1.01", "-1.001"], ["-1e9999", "-1e9998"],
        ["-1e-9999", "0"]
    ]

    for pair in pairs:
        let values = "\{\"left\":{pair[0]},\"right\":{pair[1]}\}"
        try check("left < right and right > left and left != right", values, "yes")

test "contains and default use exact numeric semantics":
    let values = "\{\"items\":[1e400,9007199254740992],\"same\":10e399,\"neighbor\":9007199254740993,\"tiny\":1e-400,\"zero\":-0e999\}"
    try check("items | contains(same)", values, "yes")
    try check("items | contains(neighbor)", values, "no")

    let template = try compile(
        "\{\{ tiny | default(\"fallback\") \}\}|\{\{ zero | default(\"fallback\") \}\}"
    )
    try expect_equal((try template.render(try parse(values))), "1e-400|fallback")

test "numbers do not become objects or strings on overflow":
    try check("left == right", "\{\"left\":1e400,\"right\":\"1e400\"\}", "no")
    try check("left == right", "\{\"left\":1e400,\"right\":\{\}\}", "no")

test "exponents larger than machine integers never expand":
    let nines = try "9".repeat(2000)
    let previous = "{try "9".repeat(1999)}8"
    let values = "\{\"left\":1e{nines},\"right\":10e{previous}\}"
    try check("left == right", values, "yes")

    let small = "\{\"left\":1e-{nines},\"right\":0.1e-{previous}\}"
    try check("left == right and left", small, "yes")

test "integer fast path agrees with exact decimal path at machine boundaries":
    let pairs = [
        ["9223372036854775807", "9223372036854775807.0"],
        ["-9223372036854775808", "-9223372036854775808.0"], ["0", "-0"]
    ]
    for pair in pairs:
        try check("left == right", "\{\"left\":{pair[0]},\"right\":{pair[1]}\}", "yes")
    try check(
        "left < right",
        "\{\"left\":9223372036854775807,\"right\":9223372036854775808\}", "yes"
    )

test "malformed raw number payloads cannot acquire numeric ordering":
    let condition = try compile(
        "\{\{ if value == value or value < value or value <= value or value > value or value >= value \}\}ordered\{\{ else \}\}unordered\{\{ end \}\}"
    )
    let truth = try compile("\{\{ if value \}\}true\{\{ else \}\}false\{\{ end \}\}")

    for raw in [
        "NaN", "Infinity", "+1", "01", "true", "[]", "\"1\"", "", "-", ".", "1.", "1e",
        "1e+", "1e-", "--1", "1e1.0", "0x10", "1_0", "1 0", "١"
    ]:
        var fields = Map[String, JsonValue]()
        fields.add("value", JsonValue.NumberValue(raw))

        let value = JsonValue.ObjectValue(fields)
        try expect_equal((try condition.render(value)), "unordered")
        try expect_equal((try truth.render(value)), "true")

test "coefficient spans preserve decimal points and implicit trailing zeros":
    let pairs = [
        ["1.2", "1.2000"], ["0.01200", "0.012"], ["120.000", "1.2e2"], ["-0.000", "0"],
        ["-0.00e99", "0.0"]
    ]
    for pair in pairs:
        try check(
            "left == right and left <= right and right <= left",
            "\{\"left\":{pair[0]},\"right\":{pair[1]}\}", "yes"
        )
    try check("left < right", "\{\"left\":1.2,\"right\":1.2001\}", "yes")
    try check("left > right", "\{\"left\":-1.2,\"right\":-1.2001\}", "yes")

test "long shared coefficient prefixes retain exact order":
    let prefix = try "23456789".repeat(125)
    let values = "\{\"left\":1.{prefix},\"right\":1.{prefix}1\}"
    try check("left < right and right > left and left != right", values, "yes")
