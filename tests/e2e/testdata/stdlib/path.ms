import {
    posix,
    win32,
    PathError,
    dirname,
    basename_without
} from "@std/path.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "POSIX paths normalize resolve parse and match without host access":
    let paths = posix()
    if paths.normalize("/a/./b/../c") != "/a/c": return panic("POSIX normalize")
    if paths.join(["/a", "b", "c.txt"]) != "/a/b/c.txt": return panic("POSIX join")
    if value(paths.relative(base: "/a/b", target: "/a/c")) != "../c": return panic(
        "POSIX relative"
    )
    if value(paths.resolve(base: "/a", parts: ["b", "../c"])) != "/a/c": return panic(
        "POSIX resolve"
    )

    let parsed = paths.parse("/a/file.tar.gz")
    if parsed.name != "file.tar" or parsed.extension != ".gz": return panic(
        "path parts"
    )
    if paths.format(parsed) != "/a/file.tar.gz": return panic("path format")
    if not value(paths.matches_glob(path: "src/main.ms", pattern: "src/*.ms")): return panic(
        "glob match"
    )
    if value(paths.matches_glob(path: "src/main.go", pattern: "src/*.ms")): return panic(
        "glob mismatch"
    )

test "Windows paths use explicit dialect on every platform":
    let paths = win32()
    if paths.separator() != "\\" or paths.delimiter() != ";": return panic(
        "Windows separators"
    )
    if not paths.is_absolute("C:\\work\\file.txt"): return panic("drive absolute")
    if paths.basename("C:\\work\\file.txt") != "file.txt": return panic(
        "Windows basename"
    )
    if paths.normalize("C:\\a\\..\\b") != "C:\\b": return panic("Windows normalize")
    if value(paths.relative(base: "C:\\a", target: "C:\\b")) != "..\\b": return panic(
        "Windows relative"
    )

test "module dirname and basename_without follow the host dialect":
    if dirname("") != ".": return panic("empty dirname")
    if basename_without(path: "dir/file.txt", suffix: ".txt") != "file": return panic(
        "basename_without suffix"
    )
    if basename_without(path: "dir/file.txt", suffix: ".md") != "file.txt": return panic(
        "basename_without keeps non-matching suffix"
    )
