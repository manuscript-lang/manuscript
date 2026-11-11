import (
	posix, win32 from "@std/os/path.ms",
	expect_equal from "@std/test/test.ms",
)

test "path suffix scans preserve Unicode component boundaries":
	paths := posix()
	slashes := "/".repeat(8192).get("")
	expect_equal(paths.basename("é.txt{slashes}"), "é.txt")?
	expect_equal(paths.basename_without("é.txt{slashes}", ".txt"), "é")?
	expect_equal(paths.extension("目录/é.txt{slashes}"), ".txt")?
	expect_equal(paths.dirname("/目录/é.txt{slashes}"), "/目录")?
	expect_equal(paths.basename(slashes), "")?
	expect_equal(paths.dirname(slashes), "/")?

test "UNC scans retain root spelling and Unicode server and share names":
	paths := win32()
	slashes := "/".repeat(8192).get("")
	root := "//{slashes}服务器/{slashes}共享/"
	spelling := "{root}a/../文件.txt"
	expect_equal(paths.parse(spelling).root, root)?
	expect_equal(paths.normalize(spelling), "{root.replace("/", "\\")}文件.txt")?
	expect_equal(paths.join([slashes.clone(), "服务器/共享"]), "\\服务器\\共享")?

test "short path scans keep empty root and incomplete UNC rules":
	paths := win32()
	expect_equal(paths.normalize("//server"), "\\server")?
	expect_equal(paths.normalize("//server////"), "\\server\\")?
	expect_equal(paths.normalize("///"), "\\")?
	expect_equal(paths.normalize("//服务器/共享"), "\\\\服务器\\共享\\")?
	expect_equal(posix().basename(""), "")?
	expect_equal(posix().basename("a.txt/"), "a.txt")?
