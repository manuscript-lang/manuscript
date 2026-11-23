// conform: tags=testing,faults,tier-io
// conform: phase=test
import (
	promise from "@std/concurrency/promise.ms",
	expect_equal, expect_error from "@std/test/test.ms",
)

fn boom(n: Int) Int!:
	xs: List[Int] := []
	return ok(xs[n])

fn fine(n: Int) Int!:
	return ok(n)

fn label(n: Int) String:
	return f"a-long-made-up-place-{n}.ms:{n} in somewhere"

test "a built site string is copied and freed when the work ends":
	p := promise[Int](fn: fine(3), site: label(7))
	expect_equal(p.wait()?, 3)?

test "a built site string is freed when the promise is dropped unwaited":
	_p := promise[Int](fn: fine(3), site: label(8))
	expect_equal(1, 1)?

test "a built site string shows in the report":
	p := promise[Int](fn: boom(3), site: label(9))
	reason := p.wait() | expect_error?
	expect_equal(
		reason.details["report"].contains(
			"at a-long-made-up-place-9.ms:9 in somewhere"
		),
		true,
	)?
