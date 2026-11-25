// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn same(a String, b String) Bool {
	return a == b
}

fn built(parts List[String]) String {
	var s = ""
	for p in parts {
		s += p
	}
	return s
}

test "equal text is equal whether stored inline, static, owned, or borrowed" {
	short := built(["ab", "cd"])
	expect_equal(same(short, "abcd"), true)?
	expect_equal(same("abcd", short), true)?
	expect_equal(same(short, built(["a", "bcd"])), true)?

	long := built(["a long string ", "past fifteen bytes"])
	expect_equal(same(long, "a long string past fifteen bytes"), true)?
	expect_equal(same(long, built(["a long string past ", "fifteen bytes"])), true)?
	expect_equal(same("  abcd ".trim(), short), true)?

	pieces := "abcd,a long string past fifteen bytes".split(",").collect()
	expect_equal(same(pieces[0], short), true)?
	expect_equal(same(pieces[1], long), true)?
	expect_equal(same(built(["", ""]), ""), true)?
}

test "different text is different at every length and kind" {
	short := built(["ab", "cd"])
	expect_equal(same(short, "abce"), false)?
	expect_equal(same(short, "abc"), false)?
	expect_equal(same(short, built(["abcd", "e"])), false)?
	expect_equal(
		same(built(["fifteen ", "bytes!!"]), built(["fifteen ", "bytes!?"])),
		false,
	)?
	expect_equal(
		same(built(["fifteen ", "bytes!!"]), built(["fifteen ", "bytes!!!"])),
		false,
	)?

	long := built(["a long string ", "past fifteen bytes"])
	expect_equal(same(long, built(["a long string ", "past fifteen bytez"])), false)?
	expect_equal(same(long, short), false)?
	expect_equal(same(built(["ab\u{0}", "c"]), "ab"), false)?
}

fn filled(n Int, at Int) String {
	var parts List[String] = []

	for i in 0..n {
		if i == at {
			parts.append("b")
		} else {
			parts.append("a")
		}
	}

	return built(parts)
}

test "owned text of one length differs at any byte, which the inline compare covers" {
	for n in 8..40 {
		for at in 0..n {
			expect_equal(same(filled(n, at), filled(n, n)), false)?
			expect_equal(same(filled(n, at), filled(n, at)), true)?
			expect_equal(same(filled(n, at), filled(n + 1, at)), false)?
		}
	}
}
