import expect_equal from "@std/test/test.ms"

test "string text helpers":
    "  a b\t c ".fields() | try expect_equal(["a", "b", "c"])
    "hello wORLD".title() | try expect_equal("Hello World")
    "xxabcxx".trim_chars("x") | try expect_equal("abc")
    "a,b,c".split_after(",") | try expect_equal(["a,", "b,", "c"])
    "Straße".equal_fold("STRASSE") | try expect_equal(true)
    "ı".equal_fold("I") | try expect_equal(true)
    "banana".count("an") | try expect_equal(2)
    "a<b>".replace_each({"<": "&lt;", ">": "&gt;"}) | try expect_equal("a&lt;b&gt;")
    "".fields() | try expect_equal(List[String]())
    "a\u{a0}b".fields() | try expect_equal(["a", "b"])
    "a1b22c".fields_by(fn c: c >= "0" and c <= "9") | try expect_equal(["a", "b", "c"])
    "aaa".count("") | try expect_equal(4)
    "aaaa".count("aa") | try expect_equal(2)
    "héllo".trim_start_chars("hé") | try expect_equal("llo")
    "abc".trim_end_chars("cb") | try expect_equal("a")
    "abc".contains_any("xyc") | try expect_equal(true)
    "héllo".index_any("lo") | try expect_equal(2)
    "abc".index_any("") | try expect_equal(none)
    "ab".split_after("") | try expect_equal(["a", "b"])
    "a,b,".split_after(",") | try expect_equal(["a,", "b,"])
    "élan vital".capitalize() | try expect_equal("Élan vital")
    "it's a dog".title() | try expect_equal("It's A Dog")
    "a1b".map_chars(fn c: if c == "1": "" else: c.upper()) | try expect_equal("AB")
    "héllo".find_char(fn c: c == "l") | try expect_equal(2)
    "aaa".replace_each({"aa": "b", "a": "c"}) | try expect_equal("bc")
    "x".replace_each(Map[String, String]()) | try expect_equal("x")

test "replace_each without replacements preserves exact text":
    let pairs = Map[String, String]()

    for text in ["", "a", "héllo 🦀", "a\u{0}b", "e\u{301}"]:
        text.replace_each(pairs) | try expect_equal(text)
        text.replace_each({"": "ignored"}) | try expect_equal(text)

    var source = "héllo 🦀"
    let copied = source.replace_each(pairs)
    source = "changed"
    copied | try expect_equal("héllo 🦀")
    source | try expect_equal("changed")
    pairs.is_empty() | try expect_equal(true)
    "".replace_each({"a": "b"}) | try expect_equal("")
    "🦀é🦀".replace_each({"🦀": "x", "é": "y"}) | try expect_equal("xyx")
    "ab".replace_each({"a": "ab"}) | try expect_equal("abb")
