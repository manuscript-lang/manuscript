// conform: tags=optional,tier-core
// conform: phase=test
import expect_equal, expect_false, expect_true from "@std/test/test.ms"

type Tok:
	s: String

// Returns its argument on one path and `none` on the other.
fn keep(t: Tok, flag: Bool) Tok?:
	if flag: return t
	return none

fn first_long(t: Tok, n: Int) Tok?:
	if t.s.length() > n:
		return t
	return none

test "a call over a temporary returns none when the callee does":
	expect_true(keep(Tok("a"), false).is_none())?
	expect_false(keep(Tok("a"), true).is_none())?
	kept := keep(Tok("b"), true)
	expect_equal(kept.get(Tok("")).s, "b")?
	dropped := keep(Tok("c"), false)
	expect_true(dropped.is_none())?

test "the argument is the result only when the callee returns it":
	expect_true(first_long(Tok("ab"), 5).is_none())?
	expect_true(first_long(Tok("abcdef"), 5).is_some())?
