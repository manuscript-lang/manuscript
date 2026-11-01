import StringCut from "@std/string.ms"
import expect_equal, expect_none, expect_ok, expect_some from "@std/test/test.ms"

fn expect_cut(actual: StringCut?, before: String, after: String) Unit!:
    let part = actual | try expect_some
    part.before | try expect_equal(before)
    return part.after | expect_equal(after)

test "cuts distinguish missing separators from empty sides":
    "name=value=rest".cut("=") | try expect_cut("name", "value=rest")
    "name=value=rest".cut_last("=") | try expect_cut("name=value", "rest")
    "=value".cut("=") | try expect_cut("", "value")
    "name=".cut_last("=") | try expect_cut("name", "")
    "=".cut("=") | try expect_cut("", "")
    "=".cut_last("=") | try expect_cut("", "")
    "name".cut("=") | try expect_none
    "name".cut_last("=") | try expect_none
    "".cut("=") | try expect_none
    "".cut_last("=") | try expect_none
    "x".cut("longer") | try expect_none
    "x".cut_last("longer") | try expect_none

test "empty separators match the first or last scalar boundary":
    "é🙂".cut("") | try expect_cut("", "é🙂")
    "é🙂".cut_last("") | try expect_cut("é🙂", "")
    "".cut("") | try expect_cut("", "")
    "".cut_last("") | try expect_cut("", "")

test "cuts find overlapping and repeated exact separators":
    "ababa".cut("aba") | try expect_cut("", "ba")
    "ababa".cut_last("aba") | try expect_cut("ab", "")
    "aaaaa".cut("aa") | try expect_cut("", "aaa")
    "aaaaa".cut_last("aa") | try expect_cut("aaa", "")
    "::a::::b::".cut("::") | try expect_cut("", "a::::b::")
    "::a::::b::".cut_last("::") | try expect_cut("::a::::b", "")

test "cuts use scalar offsets without normalizing or folding text":
    "é🙂中🙂z".cut("🙂") | try expect_cut("é", "中🙂z")
    "é🙂中🙂z".cut_last("🙂") | try expect_cut("é🙂中", "z")
    "aé🙂z".cut("é🙂") | try expect_cut("a", "z")
    "e\u{301}x".cut("\u{301}") | try expect_cut("e", "x")
    "👩\u{200d}🚀".cut("\u{200d}") | try expect_cut("👩", "🚀")
    "a\u{0}b\u{0}c".cut_last("\u{0}") | try expect_cut("a\u{0}b", "c")
    "e\u{301}".cut("é") | try expect_none
    "é".cut_last("e\u{301}") | try expect_none
    "Name".cut("n") | try expect_none

test "prefix and suffix cuts remove exactly one match":
    "preprefix".cut_prefix("pre") | try expect_some | try expect_equal("prefix")
    "suffixfix".cut_suffix("fix") | try expect_some | try expect_equal("suffix")
    "é🙂中".cut_prefix("é🙂") | try expect_some | try expect_equal("中")
    "é🙂中".cut_suffix("🙂中") | try expect_some | try expect_equal("é")
    "same".cut_prefix("same") | try expect_some | try expect_equal("")
    "same".cut_suffix("same") | try expect_some | try expect_equal("")
    "".cut_prefix("") | try expect_some | try expect_equal("")
    "".cut_suffix("") | try expect_some | try expect_equal("")
    "é🙂".cut_prefix("") | try expect_some | try expect_equal("é🙂")
    "é🙂".cut_suffix("") | try expect_some | try expect_equal("é🙂")
    "e\u{301}".cut_prefix("é") | try expect_none
    "é".cut_suffix("e\u{301}") | try expect_none
    "prefix".cut_prefix("fix") | try expect_none
    "suffix".cut_suffix("suf") | try expect_none
    "".cut_prefix("x") | try expect_none
    "".cut_suffix("x") | try expect_none
    "x".cut_prefix("longer") | try expect_none
    "x".cut_suffix("longer") | try expect_none

test "cut helpers work as bound methods and keep results independent":
    let text = "é=🙂=中"
    let cut = text.cut
    let cut_last = text.cut_last
    let cut_prefix = text.cut_prefix
    let cut_suffix = text.cut_suffix
    text.cut(separator: "=") | try expect_cut("é", "🙂=中")
    cut("=") | try expect_cut("é", "🙂=中")
    cut_last("=") | try expect_cut("é=🙂", "中")
    cut_prefix("é=") | try expect_some | try expect_equal("🙂=中")
    text.cut_suffix(suffix: "=中") | try expect_some | try expect_equal("é=🙂")
    cut_suffix("=中") | try expect_some | try expect_equal("é=🙂")

    var first = cut("=") | try expect_some
    first.before = "changed"
    cut("=") | try expect_cut("é", "🙂=中")
    text | try expect_equal("é=🙂=中")

test "large cuts preserve complete sides and handle separator-heavy text":
    let middle = "é🙂".repeat(32768) | try expect_ok
    let text = "start:".concat(middle).concat(":end")
    text.cut(":") | try expect_cut("start", middle.concat(":end"))
    text.cut_last(":") | try expect_cut("start:".concat(middle), "end")
    text.cut("absent") | try expect_none
    text.cut_last("absent") | try expect_none
    text.cut_prefix("start:") | try expect_some | try expect_equal(
        middle.concat(":end")
    )
    text.cut_suffix(":end") | try expect_some | try expect_equal(
        "start:".concat(middle)
    )

    let separators = "::".repeat(32768) | try expect_ok
    separators.cut("::") | try expect_cut("", separators.drop(2))
    separators.cut_last("::") | try expect_cut(separators.take(65534), "")

# Deliberately independent of index_of/last_index_of: compare scalars at each
# possible boundary. Inputs stay short so the simple oracle is inexpensive.
fn oracle_index(text: String, separator: String, last: Bool) Int?:
    let size = separator.length()
    var found: Int? = none

    for start in 0..(text.length() + 1):
        if start + size > text.length(): break

        var equal = true

        for offset in 0..size:
            if text.scalar_at(start + offset) != separator.scalar_at(offset):
                equal = false
                break

        if equal:
            if not last: return start

            found = start

    return found

fn check_oracle(text: String, separator: String, last: Bool) Unit!:
    let actual = if last: text.cut_last(separator) else: text.cut(separator)

    if let index = oracle_index(text, separator, last):
        let before = text.slice_scalars(0, index) | try expect_ok
        let after = text.slice_scalars(
            index + separator.length(), text.length()
        ) | try expect_ok
        return actual | expect_cut(before, after)

    return actual | expect_none

test "cuts agree with an independent scalar search oracle":
    let alphabet = ["a", "é", "🙂", "\u{301}", "\u{0}"]
    let separators = ["", "a", "é", "🙂", "\u{301}", "\u{0}", "aa", "é🙂", "🙂é", "absent"]

    for first in alphabet:
        for second in alphabet:
            for third in alphabet:
                let text = first.concat(second).concat(third)

                for separator in separators:
                    try check_oracle(text, separator, false)
                    try check_oracle(text, separator, true)
