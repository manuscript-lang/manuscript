import {expect_equal, expect_false, expect_ok, expect_true} from "@std/testing.ms"
import {posix, win32, PathError, dirname, basename_without} from "@std/path.ms"

test "POSIX paths normalize resolve parse and match without host access":
    let paths = posix()
    paths.normalize("/a/./b/../c") | try expect_equal(expected: "/a/c")
    paths.join(["/a", "b", "c.txt"]) | try expect_equal(expected: "/a/b/c.txt")
    paths.relative(base: "/a/b", target: "/a/c") | try expect_ok | try expect_equal(
        expected: "../c"
    )
    paths.resolve(base: "/a", parts: ["b", "../c"]) | try expect_ok | try expect_equal(
        expected: "/a/c"
    )
    let parsed = paths.parse("/a/file.tar.gz")
    (parsed.name != "file.tar" or parsed.extension != ".gz") | try expect_false
    paths.format(parsed) | try expect_equal(expected: "/a/file.tar.gz")
    try expect_false(
        not (
            paths.matches_glob(
                path: "src/main.ms",
                pattern: "src/*.ms"
            ) | try expect_ok
        )
    )
    try expect_false(
        (
            paths.matches_glob(
                path: "src/main.go",
                pattern: "src/*.ms"
            ) | try expect_ok
        )
    )

test "Windows paths use explicit dialect on every platform":
    let paths = win32()
    (paths.separator() != "\\" or paths.delimiter() != ";") | try expect_false
    (paths.is_absolute("C:\\work\\file.txt")) | try expect_true
    paths.basename("C:\\work\\file.txt") | try expect_equal(expected: "file.txt")
    paths.normalize("C:\\a\\..\\b") | try expect_equal(expected: "C:\\b")
    paths.relative(base: "C:\\a", target: "C:\\b") | try expect_ok | try expect_equal(
        expected: "..\\b"
    )

test "module dirname and basename_without follow the host dialect":
    dirname("") | try expect_equal(expected: ".")
    basename_without(path: "dir/file.txt", suffix: ".txt") | try expect_equal(
        expected: "file"
    )
    basename_without(path: "dir/file.txt", suffix: ".md") | try expect_equal(
        expected: "file.txt"
    )
