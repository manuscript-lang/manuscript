import (
	expect_true, expect_ok from "@std/test/test.ms",
	pipe, WriteStream from "@std/io/io.ms",
	promise, PromiseOptions, cancel_switch from "@std/concurrency/promise.ms",
	create_directory, temporary, watch from "@std/os/fs.ms",
)

// Tells the test the watch is registered, reads events until `last` shows up, tells the test again, then waits for more inside the native watcher.
fn follow(root: String, last: String, seen: WriteStream[Int]) Unit!:
	var events = try watch(root, recursive: true)
	var out = seen
	try out.write(0)

	while true:
		event := try events.next()

		if found := event:
			if found.path == last:
				try out.write(1)
		else:
			break

// A cancelled read inside the native watcher must leave the watcher to the stream that owns it. The
// frame of `WatchSource.next` held the source it took out of the stream, refilled after `pending.pop()`,
// and unwinding dropped that copy too, so the watcher (and its map of watch descriptors) was freed twice.
test "cancelling a recursive watch after a burst of events releases the watcher once":
	temp := temporary("ms-watch-cancel-") | try expect_ok
	path := temp.path()
	var ready = pipe[Int](4)
	var reader = ready.reader()
	switch := cancel_switch()
	last := "{path}/d19"
	work := promise(fn: follow(path.clone(), last.clone(), ready.writer())).with(
		options: PromiseOptions(cancel: switch.signal())
	)
	_registered := try reader.next()
	var i = 0

	while i < 20:
		try create_directory("{path}/d{i}/e/f", recursive: true)
		i += 1

	_arrived := try reader.next()
	switch.cancel()
	try expect_true(work.wait().is_error())
