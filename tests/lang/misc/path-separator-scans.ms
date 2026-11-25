// conform: tags=testing,tier-io
// conform: phase=test
import (
	posix, win32 from "@std/os/path.ms",
	expect_equal from "@std/test/test.ms",
)

test "path suffix scans preserve Unicode component boundaries" {
	paths := posix()
	slashes := "/".repeat(8192)
	expect_equal(paths.basename(f"é.txt{slashes}"), "é.txt")?
	expect_equal(paths.basename_without(f"é.txt{slashes}", ".txt"), "é")?
	expect_equal(paths.extension(f"目录/é.txt{slashes}"), ".txt")?
	expect_equal(paths.dirname(f"/目录/é.txt{slashes}"), "/目录")?
	expect_equal(paths.basename(slashes), "")?
	expect_equal(paths.dirname(slashes), "/")?
}

test "UNC scans keep root spelling in parse and collapse repeated separators in normalize" {
	paths := win32()
	slashes := "/".repeat(8192)
	root := f"//服务器/{slashes}共享/"
	spelling := f"{root}a/../文件.txt"
	expect_equal(paths.parse(spelling).root, root)?
	expect_equal(paths.normalize(spelling), "\\\\服务器\\共享\\文件.txt")?

	// More than two leading separators make a rooted path, not a UNC server.
	expect_equal(paths.normalize(f"//{slashes}服务器/共享/"), "\\服务器\\共享\\")?
	expect_equal(paths.join([slashes.clone(), "服务器/共享"]), "\\服务器\\共享")?
}

test "short path scans keep empty root and incomplete UNC rules" {
	paths := win32()
	expect_equal(paths.normalize("//server"), "\\server")?
	expect_equal(paths.normalize("//server////"), "\\server\\")?
	expect_equal(paths.normalize("///"), "\\")?
	expect_equal(paths.normalize("//服务器/共享"), "\\\\服务器\\共享\\")?
	expect_equal(posix().basename(""), "")?
	expect_equal(posix().basename("a.txt/"), "a.txt")?
}
// expect-exit: 0
// expect-tests: passed=3 failed=0
