// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	compile_glob, matches_glob, posix, win32 from "@std/os/path.ms",
	expect_equal, expect_false, expect_true from "@std/test/test.ms",
)

test "a compiled glob matches like the one-shot call" {
	g := compile_glob("/usr/**/file*.{gz,zip}")?

	for path in ["/usr/local/share/file1.gz", "/usr/file.zip", "/usr/a/b/c/file.gz"] {
		expect_true(g.matches(path)?)?
		expect_equal(g.matches(path)?, matches_glob(path, "/usr/**/file*.{gz,zip}")?)?
	}

	for path in ["/usr/local/other.gz", "/etc/file.gz", "/usr/.hidden/file.gz", ""] {
		expect_false(g.matches(path)?)?
		expect_equal(g.matches(path)?, matches_glob(path, "/usr/**/file*.{gz,zip}")?)?
	}
}

test "a compiled glob reads groups, classes and long names" {
	g := compile_glob("*(ab)+([0-9])?(x)[!z]")?
	expect_true(g.matches("abab12xq")?)?
	expect_false(g.matches("abab12xz")?)?

	deep := "a/".repeat(200) + "b"
	expect_true((compile_glob("**/b")?).matches(deep)?)?
	expect_true((compile_glob("a*a")?).matches("a".repeat(300))?)?
	expect_false((compile_glob("a*b")?).matches("a".repeat(300))?)?
}

test "dialects choose the separator and bad input is EINVAL" {
	expect_true((win32().compile_glob("C:/a/*.ms")?).matches("C:\\a\\b.ms")?)?
	expect_false((posix().compile_glob("a/*.ms")?).matches("a\\b.ms")?)?
	expect_equal(compile_glob("[").err(), Error("path: invalid input", kind: "EINVAL"))?

	g := compile_glob("*")?
	expect_equal(
		g.matches("a\u{0}").err(),
		Error("path: invalid input", kind: "EINVAL"),
	)?
	expect_equal(
		matches_glob("a", "[").err(),
		Error("path: invalid input", kind: "EINVAL"),
	)?
}
