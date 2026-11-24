// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

test "replace_each picks the first map entry that matches at a position" {
	"aaa".replace_each({"aa": "b", "a": "c"}) | expect_equal("bc")?
	"aaa".replace_each({"a": "c", "aa": "b"}) | expect_equal("ccc")?
	"banana".replace_each({"an": "AN", "na": "NA", "ban": "x"}) | expect_equal("xANa")?
}

test "replace_each handles multibyte keys, empty keys and empty values" {
	"héllo 🦀 wörld".replace_each(
		{"é": "E", "🦀": "crab", "ö": ""}
	) | expect_equal("hEllo crab wrld")?
	"🦀🦀é".replace_each({"🦀": "🦀🦀"}) | expect_equal("🦀🦀🦀🦀é")?
	"abc".replace_each({"": "x", "b": "B"}) | expect_equal("aBc")?
	"a<b>&".replace_each(
		{"<": "&lt;", ">": "&gt;", "&": "&amp;"}
	) | expect_equal("a&lt;b&gt;&amp;")?
}

test "replace_each does not rescan replacements" {
	"x".replace_each({"x": "xx"}) | expect_equal("xx")?
	"ab".replace_each({"a": "b", "b": "a"}) | expect_equal("ba")?
}

test "index_any reports the byte offset of the first scalar in the set" {
	"héllo".index_any("l") | expect_equal(3)?
	"héllo".index_any("éo") | expect_equal(1)?
	("abc".index_any("z") == null) | expect_equal(true)?
	("abc".index_any("") == null) | expect_equal(true)?
	("".index_any("a") == null) | expect_equal(true)?
	"a🦀b".index_any("🦀") | expect_equal(1)?
	"zzzzzzzzzzk".index_any("abcdefghijk") | expect_equal(10)?
}
