import (
	pipe from "@std/io/io.ms",
	expect_equal from "@std/test/test.ms",
	milliseconds from "@std/time.ms",
)

test "a stalled read times out and a ready one does not":
	var queue = pipe[Int](4)
	var out = queue.writer()
	var input = queue.reader()
	out.write(7)?

	first := input.next(timeout: milliseconds(200))?
	expect_equal(first.get(0), 7)?

	stalled := input.next(timeout: milliseconds(50))
	bad := stalled.error()
	expect_equal(bad.is_some(), true)?
	expect_equal(bad.get(Error("none")).kind, "ETIMEDOUT")?
