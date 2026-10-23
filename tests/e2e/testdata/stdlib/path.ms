import {expect_equal, expect_false} from "@std/testing.ms"
import {posix, win32, PathError, dirname, basename_without} from "@std/fs.ms"

test "POSIX paths normalize resolve parse and match without host access":
    let paths = posix()

    try expect_equal(paths.normalize("/a/./b/../c"), "/a/c")
    try expect_equal(paths.join(["/a", "b", "c.txt"]), "/a/b/c.txt")
    try expect_equal((try paths.relative("/a/b", "/a/c")), "../c")
    try expect_equal((try paths.resolve("/a", ["b", "../c"])), "/a/c")

    let parsed = paths.parse("/a/file.tar.gz")

    try expect_false(parsed.name != "file.tar" or parsed.extension != ".gz")
    try expect_equal(paths.format(parsed), "/a/file.tar.gz")
    try expect_false(not (try paths.matches_glob("src/main.ms", "src/*.ms")))
    try expect_false((try paths.matches_glob("src/main.go", "src/*.ms")))

test "Windows paths use explicit dialect on every platform":
    let paths = win32()

    try expect_false(paths.separator() != "\\" or paths.delimiter() != ";")
    try expect_false(not paths.is_absolute("C:\\work\\file.txt"))
    try expect_equal(paths.basename("C:\\work\\file.txt"), "file.txt")
    try expect_equal(paths.normalize("C:\\a\\..\\b"), "C:\\b")
    try expect_equal((try paths.relative("C:\\a", "C:\\b")), "..\\b")

test "module dirname and basename_without follow the host dialect":
    try expect_equal(dirname(""), ".")
    try expect_equal(basename_without("dir/file.txt", ".txt"), "file")
    try expect_equal(basename_without("dir/file.txt", ".md"), "file.txt")

test "glob matching rejects NUL in the path as it does in the pattern":
    let invalid: Result[Bool, PathError] = error(PathError.InvalidInput)

    try expect_equal(posix().matches_glob("a\u{0}b", "*"), invalid)
    try expect_equal(posix().matches_glob("ab", "*\u{0}"), invalid)
