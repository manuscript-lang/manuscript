import expect_equal, expect_none, expect_ok, expect_some from "@std/test/test.ms"

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

test "affix cuts work as bound methods and labeled calls":
    let text = "é=🙂=中"
    let cut_prefix = text.cut_prefix
    let cut_suffix = text.cut_suffix
    cut_prefix("é=") | try expect_some | try expect_equal("🙂=中")
    text.cut_suffix(suffix: "=中") | try expect_some | try expect_equal("é=🙂")
    cut_suffix("=中") | try expect_some | try expect_equal("é=🙂")
    text | try expect_equal("é=🙂=中")

test "large affix cuts preserve text and reject missing affixes":
    let middle = "é🙂".repeat(32768) | try expect_ok
    let text = "start:".concat(middle).concat(":end")
    text.cut_prefix("start:") | try expect_some | try expect_equal(
        middle.concat(":end")
    )
    text.cut_suffix(":end") | try expect_some | try expect_equal(
        "start:".concat(middle)
    )
    text.cut_prefix("absent") | try expect_none
    text.cut_suffix("absent") | try expect_none

# Independent scalar comparisons verify exact matching without normalization.
fn check_affix(text: String, affix: String, prefix: Bool) Unit!:
    let actual = if prefix: text.cut_prefix(affix) else: text.cut_suffix(affix)
    if affix.length() > text.length(): return actual | expect_none

    let start = if prefix: 0 else: text.length() - affix.length()
    for offset in 0..affix.length():
        if text.scalar_at(start + offset) != affix.scalar_at(offset):
            return actual | expect_none

    let kept_start = if prefix: affix.length() else: 0
    let kept_end = if prefix: text.length() else: start
    let expected = text.slice_scalars(kept_start, kept_end) | try expect_ok
    return actual | try expect_some | expect_equal(expected)

test "affix cuts agree with an independent scalar oracle":
    let alphabet = ["a", "é", "🙂", "\u{301}", "\u{0}"]
    let affixes = ["", "a", "é", "🙂", "\u{301}", "\u{0}", "aa", "é🙂", "🙂é", "absent"]

    for first in alphabet:
        for second in alphabet:
            for third in alphabet:
                let text = first.concat(second).concat(third)

                for affix in affixes:
                    try check_affix(text, affix, true)
                    try check_affix(text, affix, false)
