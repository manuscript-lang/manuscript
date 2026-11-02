import compile, RegexSpan, RegexError from "@std/string.ms"
import (
    expect_equal,
    expect_ok,
    expect_error,
    expect_some,
    expect_none
) from "@std/test/test.ms"

fn pairs(spans: List[RegexSpan]) List[List[Int]]:
    var out = List[List[Int]](reserve: spans.length())
    for span in spans: out.append([span.start, span.end])
    return out

fn slots(spans: List[RegexSpan?]) List[List[Int]?]:
    var out = List[List[Int]?](reserve: spans.length())

    for span in spans:
        if let present = span:
            out.append([present.start, present.end])
        else:
            out.append(none)

    return out

test "match spans use UTF8 byte offsets and existing empty adjacency":
    let unicode = compile("é|🙂") | try expect_ok
    unicode.find_all_spans(
        "aé🙂"
    ) | try expect_ok | pairs | try expect_equal([[1, 3], [3, 7]])

    let empty = compile("") | try expect_ok
    empty.find_all_spans(
        "é🙂"
    ) | try expect_ok | pairs | try expect_equal([[0, 0], [2, 2], [6, 6]])

    let adjacent = compile("a*") | try expect_ok
    adjacent.find_all_spans(
        "a🙂🙂a"
    ) | try expect_ok | pairs | try expect_equal([[0, 1], [5, 5], [9, 10]])

    let no_match = compile("x") | try expect_ok
    no_match.find_all_spans("é🙂", 0) | try expect_ok | pairs | try expect_equal(
        List[List[Int]]()
    )

test "capture spans distinguish no match absent groups and empty captures":
    let re = compile("(a)?()") | try expect_ok
    let first = re.capture_spans("") | try expect_ok | try expect_some
    let expected: List[List[Int]?] = [[0, 0], none, [0, 0]]
    first | slots | try expect_equal(expected)

    let absent = compile("(x)") | try expect_ok
    absent.capture_spans("abc", 0) | try expect_ok | try expect_none
    re.captures("") | try expect_equal(["", "", ""])

    let plain = compile("é") | try expect_ok
    let plain_expected: List[List[Int]?] = [[1, 3]]
    plain.capture_spans(
        "aé", 1
    ) | try expect_ok | try expect_some | slots | try expect_equal(plain_expected)
    plain.capture_spans("aé", 0) | try expect_error | try expect_equal(
        RegexError.LimitExceeded
    )

test "capture rows clear absent groups and retain all group indices":
    let re = compile("(?P<left>é)|(🙂)") | try expect_ok
    let rows = re.capture_all_spans("é🙂é", 3, 9) | try expect_ok
    rows.length() | try expect_equal(3)

    let left: List[List[Int]?] = [[0, 2], [0, 2], none]
    let right: List[List[Int]?] = [[2, 6], none, [2, 6]]
    rows[0] | slots | try expect_equal(left)
    rows[1] | slots | try expect_equal(right)

    let last: List[List[Int]?] = [[6, 8], [6, 8], none]
    rows[2] | slots | try expect_equal(last)

    let bytes = "é🙂é".to_bytes()
    let present = rows[1][2] | try expect_some
    bytes.decode_utf8_range(
        present.start, present.end
    ) | try expect_some | try expect_equal("🙂")

test "span budgets cover whole and unmatched capture slots":
    let re = compile("(a)|(b)") | try expect_ok
    re.find_all_spans(
        "ab", 2
    ) | try expect_ok | pairs | try expect_equal([[0, 1], [1, 2]])
    re.find_all_spans("ab", 1) | try expect_error | try expect_equal(
        RegexError.LimitExceeded
    )
    re.capture_spans(
        "ab", 3
    ) | try expect_ok | try expect_some | slots | try expect_equal(
        [[0, 1], [0, 1], none]
    )
    re.capture_spans("ab", 2) | try expect_error | try expect_equal(
        RegexError.LimitExceeded
    )

    let exact = re.capture_all_spans("ab", 2, 6) | try expect_ok
    exact.length() | try expect_equal(2)
    re.capture_all_spans("ab", 2, 5) | try expect_error | try expect_equal(
        RegexError.LimitExceeded
    )
    re.capture_all_spans("ab", 1, 6) | try expect_error | try expect_equal(
        RegexError.LimitExceeded
    )
    re.capture_all_spans("", 0, 0) | try expect_ok | try expect_equal(
        List[List[RegexSpan?]]()
    )

    for cap in [-1, -9223372036854775808]:
        re.find_all_spans("", cap) | try expect_error | try expect_equal(
            RegexError.InvalidInput
        )
        re.capture_spans("", cap) | try expect_error | try expect_equal(
            RegexError.InvalidInput
        )
        re.capture_all_spans("", cap, none) | try expect_error | try expect_equal(
            RegexError.InvalidInput
        )
        re.capture_all_spans("", none, cap) | try expect_error | try expect_equal(
            RegexError.InvalidInput
        )

test "span methods support bound calls and preserve anchor context":
    let re = compile("(?m)(^a)|(b$)") | try expect_ok
    let find = re.find_all_spans
    find("za b\na b", none) | try expect_ok | pairs | try expect_equal(
        [[3, 4], [5, 6], [7, 8]]
    )

    let captures = re.capture_spans
    captures("za b\na b", none) | try expect_ok | try expect_some | slots | try expect_equal(
        [[3, 4], none, [3, 4]]
    )

    let all = re.capture_all_spans
    let rows = all("za b\na b", none, none) | try expect_ok
    rows.length() | try expect_equal(3)

test "span results remain bounded for dense matches":
    let text = "é🙂".repeat(32768) | try expect_ok
    let re = compile("(é)|(🙂)") | try expect_ok
    re.find_all_spans(text, 1) | try expect_error | try expect_equal(
        RegexError.LimitExceeded
    )
    re.capture_all_spans(text, none, 3) | try expect_error | try expect_equal(
        RegexError.LimitExceeded
    )
    re.capture_spans(
        text, 3
    ) | try expect_ok | try expect_some | slots | try expect_equal(
        [[0, 2], [0, 2], none]
    )
