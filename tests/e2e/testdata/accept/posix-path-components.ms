import (
	posix from "@std/os/path.ms",
	expect_equal from "@std/test/test.ms",
)

test "POSIX extensions preserve basename and dotfile rules":
	paths := posix()
	for input in ["", "/", "////", ".", "..", ".env", "dir/.env///"]:
		expect_equal(paths.extension(input), "")?
	for input in ["...", "a.", "dir/a.///"]:
		expect_equal(paths.extension(input), ".")?
	for input in [".env.local", "dir/.env.local///"]:
		expect_equal(paths.extension(input), ".local")?
	expect_equal(paths.extension("a\\b.tar.gz"), ".gz")?
	expect_equal(paths.extension("目录/日付.文///"), ".文")?

test "POSIX parse retains original directory spelling":
	paths := posix()
	parts := paths.parse("/a//日付.tar.gz///")
	expect_equal(parts.root, "/")?
	expect_equal(parts.directory, "/a/")?
	expect_equal(parts.base, "日付.tar.gz")?
	expect_equal(parts.extension, ".gz")?
	expect_equal(parts.name, "日付.tar")?

	root := paths.parse("////")
	expect_equal(root.root, "/")?
	expect_equal(root.directory, "/")?
	expect_equal(root.base, "")?
	expect_equal(root.extension, "")?
	expect_equal(root.name, "")?

test "POSIX normalization preserves parents and trailing separators":
	paths := posix()
	expect_equal(paths.normalize(""), ".")?
	expect_equal(paths.normalize("////"), "/")?
	expect_equal(paths.normalize("a/../"), "./")?
	expect_equal(paths.normalize("/../../a/../"), "/")?
	expect_equal(paths.normalize("../../a/../b/"), "../../b/")?
	expect_equal(paths.normalize("/資料//a/../日付/"), "/資料/日付/")?
	expect_equal(paths.normalize("a\\b/./"), "a\\b/")?
