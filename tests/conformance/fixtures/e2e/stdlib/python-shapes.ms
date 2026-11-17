// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	DivMod, divmod, gcd, isqrt, lcm, max_int, min_int, pow_int from "@std/math/math.ms",
	exists, temporary_directory from "@std/os/fs.ms",
	join, stem, with_extension from "@std/os/path.ms",
	SplitParts from "@std/string.ms",
	expect_equal, expect_false, expect_true from "@std/test/test.ms",
)

test "split_once cuts at the first or last separator":
	parts := "key=a=b".split_once("=").get(SplitParts("", ""))
	expect_equal(parts.before, "key")?
	expect_equal(parts.after, "a=b")?

	last := "a/b/c".rsplit_once("/").get(SplitParts("", ""))
	expect_equal(last.before, "a/b")?
	expect_equal(last.after, "c")?
	expect_true("é→ü".split_once("→").is_some())?

test "split_once returns none for a missing or empty separator":
	expect_true("abc".split_once("=").is_none())?
	expect_true("abc".split_once("").is_none())?
	expect_true("abc".rsplit_once("").is_none())?

test "counts tallies in first-seen order":
	tally := ["b", "a", "b", "b"].counts()
	expect_equal(tally.get_or("b", 0), 3)?
	expect_equal(tally.get_or("a", 0), 1)?
	expect_equal(tally.keys(), ["b", "a"])?
	expect_equal(List[Int]().counts().length(), 0)?

test "pow_int returns none on overflow or a negative exponent":
	expect_equal(pow_int(2, 10).get(-1), 1024)?
	expect_equal(pow_int(-2, 63).get(-1), min_int)?
	expect_equal(pow_int(7, 0).get(-1), 1)?
	expect_equal(pow_int(0, 0).get(-1), 1)?
	expect_true(pow_int(2, 63).is_none())?
	expect_true(pow_int(10, 19).is_none())?
	expect_true(pow_int(2, -1).is_none())?

test "divmod floors like Python":
	pair := divmod(-7, 2).get(DivMod(0, 0))
	expect_equal(pair.quotient, -4)?
	expect_equal(pair.remainder, 1)?

	neg := divmod(7, -2).get(DivMod(0, 0))
	expect_equal(neg.quotient, -4)?
	expect_equal(neg.remainder, -1)?

	exact := divmod(-6, 3).get(DivMod(9, 9))
	expect_equal(exact.quotient, -2)?
	expect_equal(exact.remainder, 0)?
	expect_true(divmod(1, 0).is_none())?
	expect_true(divmod(min_int, -1).is_none())?
	expect_equal(divmod(max_int, -1).get(DivMod(0, 0)).quotient, -max_int)?

test "gcd lcm and isqrt":
	expect_equal(gcd(12, -18), 6)?
	expect_equal(gcd(0, 0), 0)?
	expect_equal(gcd(0, 5), 5)?
	expect_equal(lcm(4, 6), 12)?
	expect_equal(lcm(0, 6), 0)?
	expect_equal(lcm(-4, 6), 12)?
	expect_equal(isqrt(0).get(-1), 0)?
	expect_equal(isqrt(17).get(-1), 4)?
	expect_equal(isqrt(16).get(-1), 4)?
	expect_equal(isqrt(max_int).get(-1), 3037000499)?
	expect_true(isqrt(-1).is_none())?

test "path stem and with_extension":
	expect_equal(stem("a/b.tar.gz"), "b.tar")?
	expect_equal(stem(".bashrc"), ".bashrc")?
	expect_equal(stem("dir/"), "dir")?
	expect_equal(with_extension("a/b.txt", "md"), join(["a", "b.md"]))?
	expect_equal(with_extension("a/b.txt", ".md"), join(["a", "b.md"]))?
	expect_equal(with_extension("a/b", "md"), join(["a", "b.md"]))?
	expect_equal(with_extension("b.txt", ""), "b")?
	expect_equal(with_extension("/", "md"), "/")?

test "exists distinguishes absence from failure":
	dir := temporary_directory("exists-")?
	expect_true(exists(dir)?)?
	expect_false(exists(f"{dir}/missing")?)?
	expect_false(exists(f"{dir}/missing/deeper")?)?

test "take_while and drop_while split at the first failing element":
	values := [1, 2, 5, 1]
	expect_equal(values.take_while(fn x: x < 3), [1, 2])?
	expect_equal(values.drop_while(fn x: x < 3), [5, 1])?
	expect_equal(values.take_while(fn x: x < 0), List[Int]())?
	expect_equal(values.drop_while(fn x: x < 9), List[Int]())?
	expect_equal(values.take_while(fn x: x < 9), values)?
	expect_equal(List[Int]().take_while(fn x: x < 3), List[Int]())?
