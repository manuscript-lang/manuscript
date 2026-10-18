import {expect_equal, expect_false, expect_ok, expect_true, fail} from "@std/testing.ms"
import {compile, Regex, RegexError} from "@std/regex.ms"

test "regex receivers execute matching replacement and empty results":
    let regex = (compile("[0-9]+") | try expect_ok)
    (regex.matches("a12b")) | try expect_true
    regex.matches("abc") | try expect_false
    regex.find_all(text: "a12b3") | try expect_ok | try expect_equal(
        expected: ["12", "3"]
    )
    try expect_false(
        not (
            regex.find_all(text: "abc", max_matches: 0) | try expect_ok
        ).is_empty()
    )
    regex.replace_all(text: "a12b3", replacement: "#") | try expect_ok | try expect_equal(
        expected: "a#b#"
    )

test "regex rejects invalid expressions and exhausted budgets":
    match compile("["):
        ok(_): return fail("invalid pattern accepted")
        error(cause):
            try expect_equal(cause, RegexError.InvalidData)

    let regex = (compile("[0-9]+") | try expect_ok)
    let limited: Result[List[String], RegexError] = error(RegexError.LimitExceeded)
    regex.find_all(text: "1 2", max_matches: 1) | try expect_equal(expected: limited)
    let output_limit: Result[String, RegexError] = error(RegexError.LimitExceeded)
    regex.replace_all(text: "1", replacement: "long", max_bytes: 3) | try expect_equal(
        expected: output_limit
    )
