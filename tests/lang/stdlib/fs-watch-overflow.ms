// conform: tags=testing,tier-io
// conform: phase=test
import (
	WatchOptions, create_directory, temporary, watch from "@std/os/fs.ms",
	expect_ok, expect_true from "@std/test/test.ms",
)

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
	var reads = 0

	while (saw_root == false) and (reads < 16) {
		event := events.next()?
		found := event
		if (found != null) and (found.path == path) and (found.kind == "rescan") {
			saw_root = true
		}
		reads += 1
	}

	expect_true(saw_root)?
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
	var reads = 0

	while (failed == false) and (reads < 16) {
		if events.next().is_error() {
			failed = true
		}
		reads += 1
	}

	expect_true(failed)?
}
// expect-exit: 0
// expect-tests: passed=2 failed=0
