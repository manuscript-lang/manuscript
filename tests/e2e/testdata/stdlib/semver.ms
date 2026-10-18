import {parse, format, compare, Version, SemverError} from "@std/semver.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

fn failure(result: Result[Version, SemverError]) SemverError:
    if result.is_ok(): return panic("accepted")

    return result.unwrap_error()

test "semver parses and formats every component":
    let version = parse(text: "1.2.3-alpha.1+build.5") | value
    if version.major != 1 or version.minor != 2 or version.patch != 3: return panic(
        "core"
    )
    if version.prerelease != ["alpha", "1"]: return panic("prerelease")
    if version.build != ["build", "5"]: return panic("build")
    if format(version: version) != "1.2.3-alpha.1+build.5": return panic("format")
    if format(version: value(parse(text: "0.0.0"))) != "0.0.0": return panic("plain")

test "semver rejects malformed text":
    let bad = [
        "", "1", "1.2", "1.2.3.4", "v1.2.3", " 1.2.3", "01.2.3", "1.2.-3", "1.2.3-",
        "1.2.3+", "1.2.3-01", "1.2.3-a..b", "1.2.3-a_b", "1.2.3+é"
    ]
    for text in bad:
        if failure(parse(text: text)) != SemverError.InvalidData: return panic(
            "category {text}"
        )

test "semver reports numbers beyond Int":
    if failure(parse(text: "99999999999999999999.0.0")) != SemverError.OutOfRange: return panic(
        "expected out of range"
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
            let left = ordered[i].unwrap()
            let right = ordered[j].unwrap()
            if (
                compare(
                    left: value(parse(text: left)),
                    right: value(parse(text: right))
                ) != expected
            ):
                return panic("order {left} {right}")

            j = j + 1

        i = i + 1

test "semver ignores build metadata and compares huge numeric identifiers":
    let a = parse(text: "1.0.0+a") | value
    let b = parse(text: "1.0.0+b") | value
    if compare(left: a, right: b) != 0: return panic("build ignored")

    let small = parse(text: "1.0.0-99999999999999999999") | value
    let large = parse(text: "1.0.0-100000000000000000000") | value
    if compare(left: small, right: large) != -1: return panic("numeric identifiers")
    if SemverError.OutOfRange.message() != "semver: value out of range": return panic(
        "message"
    )
