// conform: tags=testing,faults,tier-io
// conform: phase=test
import (
	caller_frame, promise from "@std/concurrency/promise.ms",
	map_concurrent from "@std/concurrency/resilience.ms",
	expect_equal, expect_error from "@std/test/test.ms",
)

fn boom(n Int) Int!:
	xs List[Int] := []
	return ok(xs[n])

fn inner(n Int) Int!:
	p := promise[Int](fn: boom(n))
	return p.wait()

fn middle(n Int) Int!:
	return inner(n)

// What follows `task started by:` in a fault report.
fn started_by(reason Error) String:
	parts := reason.details["report"].split("task started by:\n")
	return parts[parts.length() - 1].trim()

test "a fault in a promise names the one line that started it":
	reason := middle(3) | expect_error?
	expect_equal(reason.kind, "EIO")?
	expect_equal(started_by(reason), "at promise-fault-started-line.ms:14 in inner")?

// A helper that starts a promise for its caller passes its caller's line on.
fn started_for(n Int, site String = caller_frame()) Int!:
	p := promise[Int](fn: boom(n), site: site)
	return p.wait()

fn outer(n Int) Int!:
	return started_for(n)

test "a helper that forwards its site names its own caller":
	reason := outer(3) | expect_error?
	expect_equal(started_by(reason), "at promise-fault-started-line.ms:36 in outer")?

fn doubled(n Int) Int:
	xs List[Int] := []
	return xs[n] * 2

fn mapped() List[Int]!:
	return map_concurrent([5, 6], 2, fn n: doubled(n))

test "map_concurrent names the line that called it":
	reason := mapped() | expect_error?
	expect_equal(started_by(reason), "at promise-fault-started-line.ms:47 in mapped")?
