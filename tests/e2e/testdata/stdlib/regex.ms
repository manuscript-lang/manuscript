import expect_equal, expect_false from "@std/test/test.ms"
import compile, RegexError from "@std/string.ms"

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
    let limited: List[String]!RegexError = error(RegexError.LimitExceeded)
    try expect_equal(regex.find_all("1 2", 1), limited)

    let output_limit: String!RegexError = error(RegexError.LimitExceeded)
    try expect_equal(regex.replace_all("1", "long", 3), output_limit)

test "regex captures groups spans and splits":
    let date = try compile("(?P<y>[0-9]\{4\})-(?P<m>[0-9]\{2\})")
    try expect_equal(date.captures("on 2026-10 ok"), ["2026-10", "2026", "10"])
    try expect_equal(date.captures("none"), [])
    try expect_equal(date.named_captures("2026-10")["y"], "2026")
    try expect_equal(date.named_captures("none").is_empty(), true)
    try expect_equal(date.find_span("on 2026-10").get(), [3, 10])
    try expect_equal(date.find_span("none").is_none(), true)
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

    let limited: List[String]!RegexError = error(RegexError.LimitExceeded)
    try expect_equal(comma.split("a,b,c", 2), limited)

test "regex repeated captures clear absent groups and preserve budgets":
    let re = try compile("(a)|(b+)")
    try expect_equal(
        (try re.captures_all("a bbb a", 3)),
        [["a", "a", ""], ["bbb", "", "bbb"], ["a", "a", ""]]
    )

    let limited: List[List[String]]!RegexError = error(RegexError.LimitExceeded)
    try expect_equal(re.captures_all("a bbb a", 2), limited)
    try expect_equal((try re.captures_all("xyz", 0)), [])

test "regex repeated template expansion preserves byte budgets":
    let re = try compile("(?P<a>a+)|(b+)")
    try expect_equal(
        (try re.replace_template("aaaaaaaa b a", "$\{a\}:$\{2\}$$", 18)),
        "aaaaaaaa:$ :b$ a:$"
    )
    try expect_equal((try re.replace_template("a b", "$$", 3)), "$ $")

    let limited: String!RegexError = error(RegexError.LimitExceeded)
    try expect_equal(re.replace_template("a b", "$$", 2), limited)
    try expect_equal((try re.replace_template("a b", "xy", 5)), "xy xy")
    try expect_equal(re.replace_template("a b", "xy", 4), limited)

test "regex named captures preserve unnamed gaps and absent groups":
    let re = try compile("(a)?(?P<first>b)?(c)(?P<empty>d*)(?P<last>e)")
    let found = re.named_captures("ce")
    try expect_equal(found.length(), 2)
    try expect_equal(found.get("first").is_none(), true)
    try expect_equal(found.get("empty").get(), "")
    try expect_equal(found.get("last").get(), "e")

test "regex capture methods preserve whole match only patterns":
    let re = try compile("\\bword\\b")
    try expect_equal(re.captures("sword word"), ["word"])
    try expect_equal(re.captures("sword"), [])
    try expect_equal(re.named_captures("word").is_empty(), true)

    let unnamed = try compile("(word)([0-9]+)")
    try expect_equal(unnamed.named_captures("word123").is_empty(), true)
    try expect_equal((try re.captures_all("sword word word", 2)), [["word"], ["word"]])

    let limited: List[List[String]]!RegexError = error(RegexError.LimitExceeded)
    try expect_equal(re.captures_all("word word", 1), limited)
    try expect_equal((try re.captures_all("sword", 0)), [])

    let empty = try compile("a*")
    try expect_equal((try empty.captures_all("a🙂🙂a", 3)), [["a"], [""], ["a"]])

    let absent = try compile("(a)?b")
    try expect_equal(absent.captures("b"), ["b", ""])
    try expect_equal((try absent.captures_all("b b")), [["b", ""], ["b", ""]])

test "regex collection budgets preserve empty adjacency and exact counts":
    let re = try compile("a*")
    try expect_equal((try re.find_all("a🙂🙂a", 3)), ["a", "", "a"])
    try expect_equal((try re.captures_all("a🙂🙂a", 3)), [["a"], [""], ["a"]])
    let find_limit: List[String]!RegexError = error(RegexError.LimitExceeded)
    let capture_limit: List[List[String]]!RegexError = error(RegexError.LimitExceeded)
    try expect_equal(re.find_all("a🙂🙂a", 2), find_limit)
    try expect_equal(re.captures_all("a🙂🙂a", 2), capture_limit)
    try expect_equal(re.find_all("", 0), find_limit)
    try expect_equal(re.captures_all("", 0), capture_limit)

    for pattern in ["x", "(x)"]:
        let matching = try compile(pattern)
        try expect_equal((try matching.find_all("none", 0)), [])
        try expect_equal((try matching.captures_all("none", 0)), [])
        try expect_equal(matching.find_all("x", 0), find_limit)
        try expect_equal(matching.captures_all("x", 0), capture_limit)
        for max in [1, 4, 8]:
            let text = try "x".repeat(max)
            try expect_equal((try matching.find_all(text, max)).length(), max)
            try expect_equal((try matching.captures_all(text, max)).length(), max)
            try expect_equal(matching.find_all(text + "x", max), find_limit)
            try expect_equal(matching.captures_all(text + "x", max), capture_limit)
