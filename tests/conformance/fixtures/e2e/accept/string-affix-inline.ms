// conform: tags=testing,strings,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn both(text String, part String) Int:
	var r = 0
	if text.starts_with(part): r += 1
	if text.ends_with(part): r += 2
	return r

test "empty, one to three byte and longer affixes":
	expect_equal(both("", ""), 3)?
	expect_equal(both("a", ""), 3)?
	expect_equal(both("", "a"), 0)?
	expect_equal(both("abc", "a"), 1)?
	expect_equal(both("abc", "c"), 2)?
	expect_equal(both("abc", "b"), 0)?
	expect_equal(both("abc", "ab"), 1)?
	expect_equal(both("abc", "bc"), 2)?
	expect_equal(both("abc", "abc"), 3)?
	expect_equal(both("abc", "abcd"), 0)?
	expect_equal(both("aXc", "abc"), 0)?

test "affixes of four to sixteen bytes, inline and heap":
	t16 := "abcdefghijklmnop"
	t17 := "abcdefghijklmnopq"
	long := "abcdefghijklmnopqrstuvwxyz0123456789"
	expect_equal(both(t16, "abcd"), 1)?
	expect_equal(both(t16, "mnop"), 2)?
	expect_equal(both(t16, "abcdefg"), 1)?
	expect_equal(both(t16, "jklmnop"), 2)?
	expect_equal(both(t16, "abcdefgh"), 1)?
	expect_equal(both(t16, "ijklmnop"), 2)?
	expect_equal(both(t16, t16), 3)?
	expect_equal(both(t17, t16), 1)?
	expect_equal(both(t17, "bcdefghijklmnopq"), 2)?
	expect_equal(both(t17, "abcdefghijklmnoq"), 0)?
	expect_equal(both(long, "abcdefghijklmnop"), 1)?
	expect_equal(both(long, "klmnopqrstuvwxyz"), 0)?
	expect_equal(both(long, "0123456789"), 2)?
	expect_equal(both(long, "abcdefghijklmnopq"), 1)?
	expect_equal(both(long, "z0123456789"), 2)?
	expect_equal(both(long, "abcdefghijklmnopZ"), 0)?
	expect_equal(both(long, long), 3)?

test "differences in the middle of an overlapped read":
	expect_equal(both("abcdefgh", "abcXefgh"), 0)?
	expect_equal(both("abcdefghijk", "abcdefXhijk"), 0)?
	expect_equal(both("xxabcdefghijk", "abcdefXhijk"), 0)?
	expect_equal(both("abcdefghijkxx", "abcdefghijk"), 1)?
	expect_equal(both("xxabcdefghijk", "abcdefghijk"), 2)?

test "multibyte text compares bytes":
	expect_equal(both("héllo wörld", "hé"), 1)?
	expect_equal(both("héllo wörld", "rld"), 2)?
	expect_equal(both("héllo wörld", "h"), 1)?
	expect_equal(both("日本語のテキスト", "日本"), 1)?
	expect_equal(both("日本語のテキスト", "スト"), 2)?
