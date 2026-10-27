# conform: tags=lists,modules,stdlib-regex,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/regex.ms
from "@std/test.ms" import expect_equal, expect_false
from "@std/string.ms" import compile, RegexError

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
