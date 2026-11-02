# conform: tags=formatter,lists,modules,parser,stdlib-regex,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/regex.ms
import expect_equal, expect_false from "@std/test/test.ms"
import compile from "@std/string.ms"

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
    try expect_equal(invalid.err(), Error("regular expression: invalid data", kind: ErrorCategory.InvalidData))

    let regex = try compile("[0-9]+")
    let limited: List[String]! = error(Error("regular expression: limit exceeded", kind: ErrorCategory.LimitExceeded))
    try expect_equal(regex.find_all("1 2", 1), limited)

    let output_limit: String! = error(Error("regular expression: limit exceeded", kind: ErrorCategory.LimitExceeded))
    try expect_equal(regex.replace_all("1", "long", 3), output_limit)
