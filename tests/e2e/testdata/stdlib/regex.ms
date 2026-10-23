import {expect_equal, expect_false} from "@std/testing.ms"
import {compile, RegexError} from "@std/string.ms"

test "regex receivers execute matching replacement and empty results":
    let regex = try compile("[0-9]+")
    try expect_false(not regex.matches("a12b"))
    try expect_false(regex.matches("abc"))
    try expect_equal((try regex.find_all("a12b3")), ["12", "3"])
    try expect_false(not (try regex.find_all("abc", 0)).is_empty())
    try expect_equal((try regex.replace_all("a12b3", "#")), "a#b#")

test "regex rejects invalid expressions and exhausted budgets":
    let invalid = compile("[")
    try expect_false(not invalid.is_error())
    try expect_equal(invalid.err(), RegexError.InvalidData)
    let regex = try compile("[0-9]+")
    let limited: Result[List[String], RegexError] = error(RegexError.LimitExceeded)
    try expect_equal(regex.find_all("1 2", 1), limited)
    let output_limit: Result[String, RegexError] = error(RegexError.LimitExceeded)
    try expect_equal(regex.replace_all("1", "long", 3), output_limit)

test "regex captures groups spans and splits":
    let date = try compile("(?P<y>[0-9]\{4\})-(?P<m>[0-9]\{2\})")
    try expect_equal(date.captures("on 2026-10 ok"), ["2026-10", "2026", "10"])
    try expect_equal(date.captures("none"), [])
    try expect_equal(date.named_captures("2026-10").get("y").get(), "2026")
    try expect_equal(date.named_captures("none").is_empty(), true)
    try expect_equal(date.find_span("on 2026-10"), [3, 10])
    try expect_equal(
        (try date.captures_all("2026-10 2027-11")),
        [["2026-10", "2026", "10"], ["2027-11", "2027", "11"]]
    )
    let comma = try compile(",\\s*")
    try expect_equal((try comma.split("a, b,c")), ["a", "b", "c"])
    try expect_equal((try comma.split("")), [""])
    let swap = try compile("(\\w+)@(?P<host>\\w+)")
    try expect_equal(
        (try swap.replace_template("me@home x@y", "$\{host\}:$1 $$")), "home:me $ y:x $"
    )
    let limited: Result[List[String], RegexError] = error(RegexError.LimitExceeded)
    try expect_equal(comma.split("a,b,c", 2), limited)
