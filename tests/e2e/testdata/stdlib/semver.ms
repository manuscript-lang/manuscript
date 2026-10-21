import {expect_equal, expect_false, expect_ok, fail} from "@std/testing.ms"
import TextError from "@std/core.ms"
import {parse, format, compare, Version, SemverError} from "@std/semver.ms"

fn failure(result: Result[Version, SemverError]) Result[SemverError, Error]:
    match result:
        ok(_): return error(TextError("accepted"))
        error(cause): return ok(cause)

test "semver parses and formats every component":
    let version = (parse(text: "1.2.3-alpha.1+build.5") | try expect_ok)
    (version.major != 1 or version.minor != 2 or version.patch != 3) | try expect_false
    version.prerelease | try expect_equal(expected: ["alpha", "1"])
    version.build | try expect_equal(expected: ["build", "5"])
    format(version: version) | try expect_equal(expected: "1.2.3-alpha.1+build.5")
    format(version: (parse(text: "0.0.0") | try expect_ok)) | try expect_equal(
        expected: "0.0.0"
    )

test "semver rejects malformed text":
    let bad = [
        "", "1", "1.2", "1.2.3.4", "v1.2.3", " 1.2.3", "01.2.3", "1.2.-3", "1.2.3-",
        "1.2.3+", "1.2.3-01", "1.2.3-a..b", "1.2.3-a_b", "1.2.3+é"
    ]
    for text in bad:
        if (try failure(parse(text: text))) != SemverError.InvalidData: return fail(
            "category {text}"
        )

test "semver reports numbers beyond Int":
    (try failure(parse(text: "99999999999999999999.0.0"))) | try expect_equal(
        expected: SemverError.OutOfRange
    )

test "semver orders by precedence":
    let ordered = [
        "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta",
        "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.0.1", "1.1.0",
        "2.0.0", "10.0.0"
    ]
    var i = 0

    while i < ordered.length():
        var j = 0

        while j < ordered.length():
            var expected = 0
            if i < j: expected = -1
            if i > j: expected = 1
            let left = ordered[i]
            let right = ordered[j]
            if (
                compare(
                    left: (parse(text: left) | try expect_ok),
                    right: (parse(text: right) | try expect_ok)
                ) != expected
            ): return fail("order {left} {right}")

            j = j + 1

        i = i + 1

test "semver ignores build metadata and compares huge numeric identifiers":
    let a = (parse(text: "1.0.0+a") | try expect_ok)
    let b = (parse(text: "1.0.0+b") | try expect_ok)
    compare(left: a, right: b) | try expect_equal(expected: 0)
    let small = (parse(text: "1.0.0-99999999999999999999") | try expect_ok)
    let large = (parse(text: "1.0.0-100000000000000000000") | try expect_ok)
    compare(left: small, right: large) | try expect_equal(expected: -1)
    (
        SemverError.OutOfRange.message() | try expect_equal(
            expected: "semver: value out of range"
        )
    )
