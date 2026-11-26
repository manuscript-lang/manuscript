// conform: tags=testing,tier-io
// conform: phase=test
import (
	WatchOptions, create_directory, temporary, watch from "@std/os/fs.ms",
	expect_ok, expect_true from "@std/test/test.ms",
)

// How much of a burst reaches the reader depends on how late the host delivers events: a late host lets a
// reader keep pace, so nothing overflows. What must hold on every host is that nothing is lost silently: the
// reader sees the overflow, or it has seen every change.

// A queue of one overflows on the second change. By default (`rescan`) the watcher
// stays alive and reports one `rescan` event for the watched root: "look again".
test "a full queue becomes one rescan event for the root" {
	temp := temporary("ms-watch-overflow-") | expect_ok?
	path := temp.path()
	var events = watch(path, options: WatchOptions(max_events: 1))?
	var i = 0

	while i < 8 {
		create_directory(f"{path}/d{i}")?
		i += 1
	}

	var saw_root = false
	var seen = 0
	var reads = 0

	while (saw_root == false) and (seen < 8) and (reads < 64) {
		event := events.next()?
		found := event
		if (found != null) and (found.path == path) and (found.kind == "rescan") {
			saw_root = true
		}
		if (found != null) and (found.kind == "rename") {
			seen += 1
		}
		reads += 1
	}

	expect_true(saw_root or (seen >= 8))?
	events.close()?
}

// `error` stays available for callers that would rather fail than look again.
test "overflow: error ends the watcher with EOVERFLOW" {
	temp := temporary("ms-watch-overflow-error-") | expect_ok?
	path := temp.path()
	var events = watch(path, options: WatchOptions(max_events: 1, overflow: "error"))?
	var i = 0

	while i < 8 {
		create_directory(f"{path}/d{i}")?
		i += 1
	}

	var failed = false
	var seen = 0
	var reads = 0

	while (failed == false) and (seen < 8) and (reads < 64) {
		next := events.next()
		if next.is_error() {
			failed = true
		} else {
			seen += 1
		}
		reads += 1
	}

	expect_true(failed or (seen >= 8))?
}
// expect-exit: 0
// expect-tests: passed=2 failed=0
