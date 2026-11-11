// conform: tags=testing,tier-io
// conform: phase=test
import (
	promise, wait_all from "@std/concurrency/promise.ms",
	read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

fn size(path: String) Int!:
	data := read_file(path).wait()?
	return ok(data.length())

test "blocking file reads work from promises on any thread":
	dir := temporary("manuscript-promise-") | expect_ok?
	path := "{dir.path()}/data"
	write_file(path, "0123456789").wait()?

	all := wait_all(
		[
			promise(fn: size(path)),
			promise(fn: size(path)),
			promise(fn: size(path)),
		]
	)
	for n in all.get([]):
		expect_equal(n, 10)?
