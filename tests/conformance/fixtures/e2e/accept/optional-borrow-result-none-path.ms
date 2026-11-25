// conform: tags=optional,tier-core
// conform: phase=test
import expect_equal, expect_false, expect_true from "@std/test/test.ms"

type Tok {
	s String
}

// Returns its argument on one path and `null` on the other.
fn keep(hold t Tok, flag Bool) &Tok? {
	if flag { return t }
	return null
}

fn first_long(hold t Tok, n Int) &Tok? {
	if t.s.length() > n { return t }
	return null
}

test "a call over a temporary returns none when the callee does" {
	expect_true(keep(Tok("a"), false) == null)?
	expect_false(keep(Tok("a"), true) == null)?

	kept := keep(Tok("b"), true)
	expect_equal((kept or Tok("")).s, "b")?

	dropped := keep(Tok("c"), false)
	expect_true(dropped == null)?
}

test "the argument is the result only when the callee returns it" {
	expect_true(first_long(Tok("ab"), 5) == null)?
	expect_true(first_long(Tok("abcdef"), 5) != null)?
}
