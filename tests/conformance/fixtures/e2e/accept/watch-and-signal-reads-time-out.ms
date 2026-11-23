// conform: tags=testing,tier-io
// conform: phase=test
import (
	WatchOptions, temporary, watch from "@std/os/fs.ms",
	watch_signals from "@std/os/process.ms",
	expect_equal, expect_true from "@std/test/test.ms",
	milliseconds, monotonic from "@std/time.ms",
)

test "a bounded read of an idle native watcher times out":
	dir := temporary("manuscript-watch-timeout-")?
	var events = watch(dir.path())?
	started := monotonic()
	stalled := events.next(timeout: milliseconds(100))
	expect_equal(stalled.err().kind, "ETIMEDOUT")?
	expect_true(monotonic().difference(started).to_milliseconds() < 5000)?

test "a bounded read of an idle polling watcher times out":
	dir := temporary("manuscript-watch-poll-timeout-")?
	var events = watch(dir.path(), options: WatchOptions(interval: milliseconds(20)))?
	stalled := events.next(timeout: milliseconds(100))
	expect_equal(stalled.err().kind, "ETIMEDOUT")?

test "a bounded read of a signal stream with no signal times out":
	var signals = watch_signals([2], null)?
	stalled := signals.next(timeout: milliseconds(100))
	expect_equal(stalled.err().kind, "ETIMEDOUT")?
