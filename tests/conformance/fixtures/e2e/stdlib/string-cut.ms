// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal, expect_none, expect_ok, expect_some from "@std/test/test.ms"

test "prefix and suffix cuts remove exactly one match":
	"preprefix".cut_prefix("pre") | expect_some? | expect_equal("prefix")?
	"suffixfix".cut_suffix("fix") | expect_some? | expect_equal("suffix")?
	"é🙂中".cut_prefix("é🙂") | expect_some? | expect_equal("中")?
	"é🙂中".cut_suffix("🙂中") | expect_some? | expect_equal("é")?
	"same".cut_prefix("same") | expect_some? | expect_equal("")?
	"same".cut_suffix("same") | expect_some? | expect_equal("")?
	"".cut_prefix("") | expect_some? | expect_equal("")?
	"".cut_suffix("") | expect_some? | expect_equal("")?
	"é🙂".cut_prefix("") | expect_some? | expect_equal("é🙂")?
	"é🙂".cut_suffix("") | expect_some? | expect_equal("é🙂")?
	"e\u{301}".cut_prefix("é") | expect_none?
	"é".cut_suffix("e\u{301}") | expect_none?
	"prefix".cut_prefix("fix") | expect_none?
	"suffix".cut_suffix("suf") | expect_none?
	"".cut_prefix("x") | expect_none?
	"".cut_suffix("x") | expect_none?
	"x".cut_prefix("longer") | expect_none?
	"x".cut_suffix("longer") | expect_none?

test "affix cuts work as bound methods and labeled calls":
	text := "é=🙂=中"
	cut_prefix := text.cut_prefix
	cut_suffix := text.cut_suffix
	(cut_prefix("é=") | expect_some? | expect_equal("🙂=中")?)
	(text.cut_suffix(suffix: "=中") | expect_some? | expect_equal("é=🙂")?)
	(cut_suffix("=中") | expect_some? | expect_equal("é=🙂")?)
	text | expect_equal("é=🙂=中")?

test "large affix cuts preserve text and reject missing affixes":
	middle := "é🙂".repeat(32768) | expect_ok?
	text := "start:".concat(middle).concat(":end")
	(text.cut_prefix("start:") | expect_some? | expect_equal(middle.concat(":end"))?)
	(text.cut_suffix(":end") | expect_some? | expect_equal("start:".concat(middle))?)
	text.cut_prefix("absent") | expect_none?
	text.cut_suffix("absent") | expect_none?

// Independent scalar comparisons verify exact matching without normalization.
fn check_affix(text: String, affix: String, prefix: Bool) Unit!:
	actual := if prefix: text.cut_prefix(affix) else: text.cut_suffix(affix)
	if affix.length() > text.length(): return actual | expect_none

	start := if prefix: 0 else: text.length() - affix.length()
	for offset in 0..affix.length():
		if text.scalar_at(start + offset) != affix.scalar_at(offset):
			return actual | expect_none

	kept_start := if prefix: affix.length() else: 0
	kept_end := if prefix: text.length() else: start
	expected := text.slice_scalars(kept_start, kept_end) | expect_ok?
	return (
		actual
		| expect_some?
		| expect_equal(expected)
	)

test "affix cuts agree with an independent scalar oracle":
	alphabet := ["a", "é", "🙂", "\u{301}", "\u{0}"]
	affixes := ["", "a", "é", "🙂", "\u{301}", "\u{0}", "aa", "é🙂", "🙂é", "absent"]

	for first in alphabet:
		for second in alphabet:
			for third in alphabet:
				text := first.concat(second).concat(third)

				for affix in affixes:
					check_affix(text, affix, true)?
					check_affix(text, affix, false)?
