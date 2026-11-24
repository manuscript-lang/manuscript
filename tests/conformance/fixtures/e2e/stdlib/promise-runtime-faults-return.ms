// conform: tags=testing,faults,tier-io
// conform: phase=test
import (
	Placement, PromiseOptions, promise from "@std/concurrency/promise.ms",
	expect_equal, expect_error, expect_true from "@std/test/test.ms",

	msrt_group_free,
	msrt_group_join,
	msrt_group_new,
	msrt_group_next,
	msrt_group_poll,
	msrt_promise_drop,
	msrt_promise_sleep,
	msrt_promise_wait_any from "@std/internal/promises.ms",
)

// A fault the promise runtime raises returns through the frames of the work: the waiter
// reads it as EIO with the report, and the thread goes on. The work runs on this
// thread, so a promise made by the test is the work's own too.
fn report_of(move work fn() Int!) String!:
	here := PromiseOptions(placement: Placement.Here)
	reason := promise[Int](() => work(), options: here).wait() | expect_error?
	expect_equal(reason.kind, "EIO")?
	return ok(reason.details["report"].clone())

fn next_of_no_group() Int!:
	return ok(msrt_group_next(999))

fn poll_of_no_group() Int!:
	return ok(msrt_group_poll(999))

fn join_of_no_group() Int!:
	return ok(msrt_group_join(999, [], 0))

fn free_of_no_group() Int!:
	msrt_group_free(999)
	return ok(0)

fn wait_twice_on(id Int) Int!:
	return ok(msrt_promise_wait_any([id, id], -1))

test "a call on a wait group that does not exist faults the work":
	expect_true(report_of(next_of_no_group)?.contains("promise: no such wait group"))?
	expect_true(report_of(poll_of_no_group)?.contains("promise: no such wait group"))?
	expect_true(report_of(join_of_no_group)?.contains("promise: no such wait group"))?
	expect_true(report_of(free_of_no_group)?.contains("promise: no such wait group"))?

test "a second waiter on one promise faults and leaves the promise waitable":
	id := msrt_promise_sleep(60000000000)
	report := report_of(() => wait_twice_on(id))?
	expect_true(report.contains("another task is already waiting on this promise"))?

	// The wait token the failed call had set is taken back: a wait works and times out.
	expect_equal(msrt_promise_wait_any([id], 1000000), -1)?
	msrt_promise_drop(id)

test "groups and promises work after the faults":
	group := msrt_group_new()
	id := msrt_promise_sleep(1000000)
	expect_equal(msrt_group_join(group, [id], 0), 1)?
	expect_equal(msrt_group_next(group), 0)?
	expect_equal(msrt_group_next(group), -1)?
	msrt_group_free(group)
	expect_equal(msrt_promise_wait_any([id], -1), 0)?
	msrt_promise_drop(id)
	expect_equal(promise[Int](() => ok(3)).wait()?, 3)?
