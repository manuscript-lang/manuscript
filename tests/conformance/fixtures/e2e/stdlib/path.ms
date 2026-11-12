// conform: tags=interpolation,match,modules,stdlib-path,stdlib-testing,testing,tier-io,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/stdlib/path.ms
import expect_equal, expect_false from "@std/test/test.ms"
import basename_without, dirname, posix, win32 from "@std/os/path.ms"

test "POSIX paths normalize resolve parse and match without host access":
    paths := posix()
    expect_equal(paths.normalize("/a/./b/../c"), "/a/c")?
    expect_equal(paths.join(["/a", "b", "c.txt"]), "/a/b/c.txt")?
    expect_equal((paths.relative("/a/b", "/a/c")?), "../c")?
    expect_equal((paths.resolve("/a", ["b", "../c"])?), "/a/c")?

    parsed := paths.parse("/a/file.tar.gz")
    expect_false(parsed.name != "file.tar" or parsed.extension != ".gz")?
    expect_equal(paths.format(parsed), "/a/file.tar.gz")?
    expect_false(not (paths.matches_glob("src/main.ms", "src/*.ms")?))?
    expect_false((paths.matches_glob("src/main.go", "src/*.ms")?))?

test "Windows paths use explicit dialect on every platform":
    paths := win32()
    expect_false(paths.separator() != "\\" or paths.delimiter() != ";")?
    expect_false(not paths.is_absolute("C:\\work\\file.txt"))?
    expect_equal(paths.basename("C:\\work\\file.txt"), "file.txt")?
    expect_equal(paths.normalize("C:\\a\\..\\b"), "C:\\b")?
    expect_equal((paths.relative("C:\\a", "C:\\b")?), "..\\b")?

test "module dirname and basename_without follow the host dialect":
    expect_equal(dirname(""), ".")?
    expect_equal(basename_without("dir/file.txt", ".txt"), "file")?
    expect_equal(basename_without("dir/file.txt", ".md"), "file.txt")?

test "glob matching rejects NUL in the path as it does in the pattern":
    invalid: Bool! := error(Error("path: invalid input", kind: "EINVAL"))
    expect_equal(posix().matches_glob("a\u{0}b", "*"), invalid)?
    expect_equal(posix().matches_glob("ab", "*\u{0}"), invalid)?

test "POSIX resolution preserves resets separators and all input validation":
	paths := posix()
	expect_equal((paths.resolve("/base/", ["a", "", "b/"])?), "/base/a/b")?
	expect_equal((paths.resolve("/base", ["a", "//root///", ".", "../é🙂", ""])?), "/é🙂")?
	expect_equal(
		(paths.resolve("/", ["", "////", "../", "", "é🙂//", "..", "a/"])?),
		"/a",
	)?
	expect_equal((paths.resolve("//", [])?), "/")?
	expect_equal((paths.resolve("/base", ["a\\b"])?), "/base/a\\b")?

	invalid: String! := error(Error("path: invalid input", kind: "EINVAL"))
	expect_equal(paths.resolve("relative", ["/absolute"]), invalid)?
	expect_equal(paths.resolve("/bad\u{0}", ["/absolute"]), invalid)?
	expect_equal(paths.resolve("/base", ["bad\u{0}", "/absolute"]), invalid)?
	expect_equal(paths.resolve("/base", ["/absolute", "bad\u{0}"]), invalid)?

test "POSIX resolution handles long relative tails and absolute resets":
	paths := posix()
	var parts: List[String] = []
	for unused in 0..512:
		parts.append("segment")
	expect_equal((paths.resolve("/base/", parts)?), "/base/{parts.join("/")}")?
	parts.append("/reset/")
	expect_equal((paths.resolve("/base/", parts)?), "/reset")?

	var parents: List[String] = []
	for unused in 0..512:
		parents.append("a/..")
	expect_equal((paths.resolve("/base/", parents)?), "/base")?
