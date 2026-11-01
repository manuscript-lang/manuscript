import expect_equal from "@std/test/test.ms"
import Duration, TimeError, parse_duration, nanoseconds from "@std/os/time.ms"

test "duration parser accepts units, signs, components and Unicode microseconds":
    let examples = [
        "1ns", "1us", "1µs", "1μs", "1ms", "1s", "1m", "1h", "1h30m", "+1h30m",
        "-1h30m", "1s2h3m", "1s2s", ".5s", "1.s", "01.050s"
    ]
    let nanos = [
        1, 1000, 1000, 1000, 1000000, 1000000000, 60000000000, 3600000000000,
        5400000000000, 5400000000000, -5400000000000, 7381000000000, 3000000000,
        500000000, 1000000000, 1050000000
    ]
    for i in 0..examples.length():
        try expect_equal(parse_duration(examples.get(i)), ok(nanoseconds(nanos.get(i))))

test "duration parser canonicalizes signed and sub-nanosecond zero":
    for text in ["0", "+0", "-0", "0s", "-0.0h", "+.0μs", ".9ns", "-.9ns", "0.9ns0.9ns"]:
        let value = try parse_duration(text)
        try expect_equal(value.to_nanoseconds(), 0)
        try expect_equal(value.to_string(), "0s")

test "duration fractions truncate exactly without rounding or a precision cap":
    let examples = [
        "1.9999us", "-1.9999us", "1.000000000999s", ".000000000999s",
        ".000000000000277777777777777777777777777777777777777777777777h",
        ".000000000000277777777777777777777777777777777777777777777778h",
        ".333333333333333333333333333333333333333333333333333333333333m",
        ".333333333333333333333333333333333333333333333333333333333334m"
    ]
    let nanos = [1999, -1999, 1000000000, 0, 0, 1, 19999999999, 20000000000]
    for i in 0..examples.length():
        try expect_equal(parse_duration(examples.get(i)), ok(nanoseconds(nanos.get(i))))

test "duration parser round trips formatter branches and signed extrema":
    let values = [
        -9223372036854775807 - 1, -9223372036854775807, -3600000000000, -90500000000,
        -1000000000, -999999999, -1000000, -999999, -1500, -1000, -999, -1, 0, 1, 999,
        1000, 1500, 999999, 1000000, 999999999, 1000000000, 90500000000, 3600000000000,
        9223372036854775807
    ]

    for n in values:
        let duration = nanoseconds(n)
        try expect_equal(parse_duration(duration.to_string()), ok(nanoseconds(n)))

    try expect_equal(
        parse_duration("-9223372036854775808ns"),
        ok(nanoseconds(-9223372036854775807 - 1))
    )
    try expect_equal(
        parse_duration("9223372036854775807ns"), ok(nanoseconds(9223372036854775807))
    )
    try expect_equal(
        parse_duration("9223372036.854775807999999s"),
        ok(nanoseconds(9223372036854775807))
    )
    try expect_equal(
        parse_duration("-9223372036.854775808999999s"),
        ok(nanoseconds(-9223372036854775807 - 1))
    )
    try expect_equal(
        parse_duration("9223372036854775807.999ns"),
        ok(nanoseconds(9223372036854775807))
    )
    try expect_equal(
        parse_duration("-9223372036854775808.999ns"),
        ok(nanoseconds(-9223372036854775807 - 1))
    )
    try expect_equal(
        parse_duration("9223372036854775807ns.999ns"),
        ok(nanoseconds(9223372036854775807))
    )

test "duration overflow is an expected range error":
    let invalid: Duration!TimeError = error(TimeError.OutOfRange)
    for text in [
        "9223372036854775808ns", "-9223372036854775809ns", "9223372036.854775808s",
        "-9223372036.854775809s", "2562047h47m16.854775808s",
        "-2562047h47m16.854775809s", "9223372036854775807ns1ns",
        "-9223372036854775808ns1ns", "9223372036854775808h",
        "999999999999999999999999999999999999999s"
    ]:
        try expect_equal(parse_duration(text), invalid)

test "duration parser rejects malformed input and gives syntax errors precedence":
    let invalid: Duration!TimeError = error(TimeError.InvalidData)
    for text in [
        "", "+", "-", ".", ".s", "00", "1", "0.0", "1d", "1S", "1e3s", "1_000s", "--1s",
        "1s-2s", "1s+2s", "1..0s", "1.2.3s", "1s.", "1msx", "ns", "1u", "1µ", "1μ",
        "1µss", "1μss", "1µm", "１s", "1秒", " 1s", "1s ", "1 s", "1h 2m", "1\ts", "1s\n",
        "1\u{0000}s", "999999999999999999999999999999999999999x",
        "9223372036854775808ns!", "9223372036854775808ns1e3s",
        "999999999999999999999999999999999999999",
        "1h999999999999999999999999999999999999999..µs"
    ]:
        try expect_equal(parse_duration(text), invalid)

test "duration parsing stays exact for long leading zeros and fractions":
    let zeros = try "0".repeat(10000)
    try expect_equal(parse_duration("{zeros}1ns"), ok(nanoseconds(1)))
    try expect_equal(parse_duration("1.{zeros}1s"), ok(nanoseconds(1000000000)))
    try expect_equal(parse_duration("0.{zeros}1h"), ok(nanoseconds(0)))

    let invalid: Duration!TimeError = error(TimeError.InvalidData)
    try expect_equal(parse_duration("0.{zeros}1h!"), invalid)

    let nines = try "9".repeat(10000)
    try expect_equal(parse_duration("{nines}ns!"), invalid)

    let overflow: Duration!TimeError = error(TimeError.OutOfRange)
    try expect_equal(parse_duration("{nines}ns"), overflow)
