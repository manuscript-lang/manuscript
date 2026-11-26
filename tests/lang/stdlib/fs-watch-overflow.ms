// conform: tags=testing,tier-io
// conform: phase=test
import (
	WatchOptions, create_directory, temporary, watch from "@std/os/fs.ms",
	expect_ok, expect_true from "@std/test/test.ms",
)

// A queue of one overflows on the second change. With policy `rescan` the watcher
// stays alive and reports one change of the watched root, which means "look again".
test "a rescan watcher turns a full queue into a change of its root" {
	temp := temporary("ms-watch-overflow-") | expect_ok?
	path := temp.path()
	var events = watch(path, options: WatchOptions(max_events: 1, overflow: "rescan"))?
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
		if (found != null) and (found.path == path) {
			saw_root = true
		}
		reads += 1
	}

	expect_true(saw_root)?
	events.close()?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
