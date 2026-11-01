import posix from "@std/os/fs.ms"
import expect_equal from "@std/test/test.ms"

test "POSIX extensions preserve basename and dotfile rules":
    let paths = posix()
    for input in ["", "/", "////", ".", "..", ".env", "dir/.env///"]:
        try expect_equal(paths.extension(input), "")
    for input in ["...", "a.", "dir/a.///"]:
        try expect_equal(paths.extension(input), ".")
    for input in [".env.local", "dir/.env.local///"]:
        try expect_equal(paths.extension(input), ".local")
    try expect_equal(paths.extension("a\\b.tar.gz"), ".gz")
    try expect_equal(paths.extension("目录/日付.文///"), ".文")

test "POSIX parse retains original directory spelling":
    let paths = posix()
    let parts = paths.parse("/a//日付.tar.gz///")
    try expect_equal(parts.root, "/")
    try expect_equal(parts.directory, "/a/")
    try expect_equal(parts.base, "日付.tar.gz")
    try expect_equal(parts.extension, ".gz")
    try expect_equal(parts.name, "日付.tar")

    let root = paths.parse("////")
    try expect_equal(root.root, "/")
    try expect_equal(root.directory, "/")
    try expect_equal(root.base, "")
    try expect_equal(root.extension, "")
    try expect_equal(root.name, "")

test "POSIX normalization preserves parents and trailing separators":
    let paths = posix()
    try expect_equal(paths.normalize(""), ".")
    try expect_equal(paths.normalize("////"), "/")
    try expect_equal(paths.normalize("a/../"), "./")
    try expect_equal(paths.normalize("/../../a/../"), "/")
    try expect_equal(paths.normalize("../../a/../b/"), "../../b/")
    try expect_equal(paths.normalize("/資料//a/../日付/"), "/資料/日付/")
    try expect_equal(paths.normalize("a\\b/./"), "a\\b/")
