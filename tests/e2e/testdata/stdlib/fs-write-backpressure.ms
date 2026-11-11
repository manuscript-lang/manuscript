import (
	Bytes from "@std/bytes.ms",
	Promise, promise, wait_all from "@std/concurrency/promise.ms",
	read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

fn write_one(path: String, data: Bytes) fn() Unit!:
	return fn: write_file(path.clone(), data, replace: true).wait()

test "more large writes than pool slots all complete":
	dir := temporary("manuscript-backpressure-") | expect_ok?
	data := ("x".repeat(256 * 1024) | expect_ok?).to_bytes()
	var writers: List[Promise[Unit]] = []
	for index in 0..24:
		writers.append(promise(write_one("{dir.path()}/f{index}", data.clone())))

	done := wait_all(writers) | expect_ok?
	done.length() | expect_equal(24)?

	for index in 0..24:
		back := read_file("{dir.path()}/f{index}").wait() | expect_ok?
		back.length() | expect_equal(256 * 1024)?
