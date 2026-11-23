// conform: tags=testing,faults,tier-io
// conform: phase=test
import (
	promise from "@std/concurrency/promise.ms",
	expect_equal, expect_error from "@std/test/test.ms",
)

fn boom(n: Int) Int!:
	xs: List[Int] := []
	return ok(xs[n])

fn inner(n: Int) Int!:
	p := promise[Int](fn: boom(n))
	return p.wait()

fn middle(n: Int) Int!:
	return inner(n)

// What follows `task started by:` in a fault report.
fn started_by(reason: Error) String:
	parts := reason.details["report"].split("task started by:\n")
	return parts[parts.length() - 1].trim()

test "a fault in a promise names the one line that started it":
	reason := middle(3) | expect_error?
	expect_equal(reason.kind, "EIO")?
	expect_equal(started_by(reason), "at promise-fault-started-line.ms:13 in inner")?
