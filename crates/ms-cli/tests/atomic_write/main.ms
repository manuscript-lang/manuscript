import (
	Bytes from "@std/bytes.ms",
	expect_equal from "@std/test/test.ms",
)

// Test double: production finish_atomic is appended verbatim by the Rust harness.
// No OS or scheduler timing is needed to make close fail after a successful sync.
type FileHandle:
	write_error: Bool = false
	chmod_error: Bool = false
	sync_error: Bool = false
	close_error: Bool = false

impl FileHandle:
	fn write(data: Bytes) Unit!:
		print("write")
		if self.write_error: return error(Error("write", kind: "write"))

	fn chmod(mode: Int) Unit!:
		print("chmod")
		if self.chmod_error: return error(Error("chmod", kind: "chmod"))

	fn sync() Unit!:
		print("sync")
		if self.sync_error: return error(Error("sync", kind: "sync"))

	var fn close() Unit!:
		print("close")
		if self.close_error: return error(Error("close", kind: "close"))

fn remove(path: String) Unit!:
	print("remove {path}")
	if path == "cleanup-error": return error(Error("cleanup", kind: "cleanup"))

fn rename(source: String, destination: String) Unit!:
	print("rename {source} {destination}")
	if destination == "rename-error": return error(Error("rename", kind: "rename"))

fn report(result: Unit!) Unit:
	if result.is_error(): print(result.err().kind.get())
	else: print("ok")

fn main() Unit!:
	expect_equal(temporary_name("config.json", "s"), ".config.json.s.tmp")?
	expect_equal(temporary_name("資料/config.json", "s"), "資料/.config.json.s.tmp")?
	expect_equal(temporary_name("dir/設定.json", "s"), "dir/.設定.json.s.tmp")?
	expect_equal(temporary_name("C:\\資料\\設定.json", "s"), "C:\\資料\\.設定.json.s.tmp")?

	long := "ñ".repeat(40)?
	short := "ñ".repeat(32)?
	expect_equal(temporary_name("dir/{long}", "s"), "dir/.{short}.s.tmp")?
	print("names ok")
	print("close failure")
	report(
		finish_atomic(
			FileHandle(close_error: true), "tmp", "target", Bytes([]), none
		)
	)
	print("write wins")
	report(
		finish_atomic(
			FileHandle(write_error: true, close_error: true), "tmp", "target",
			Bytes([]), none
		)
	)
	print("chmod wins")
	report(
		finish_atomic(
			FileHandle(chmod_error: true, close_error: true), "tmp", "target",
			Bytes([]), 420
		)
	)
	print("sync wins")
	report(
		finish_atomic(
			FileHandle(sync_error: true, close_error: true), "tmp", "target", Bytes([]),
			none
		)
	)
	print("cleanup cannot hide close")
	report(
		finish_atomic(
			FileHandle(close_error: true), "cleanup-error", "target", Bytes([]), none
		)
	)
	print("success")
	report(finish_atomic(FileHandle(), "tmp", "target", Bytes([]), 420))
	print("rename failure")
	report(finish_atomic(FileHandle(), "tmp", "rename-error", Bytes([]), none))
