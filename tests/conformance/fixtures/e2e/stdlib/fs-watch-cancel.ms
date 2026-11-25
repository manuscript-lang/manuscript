// conform: tags=testing,tier-io
// conform: phase=test
import (
	PromiseOptions, cancel_switch, promise from "@std/concurrency/promise.ms",
	WriteStream, pipe from "@std/io/io.ms",
	WatchOptions, create_directory, temporary, watch from "@std/os/fs.ms",
	expect_ok, expect_true from "@std/test/test.ms",
)

// The burst raises more events than the default queue holds on a host that reports
// every level of a new directory (Windows), so the queue is sized for it. Tells the
// test the watch is registered, reads events until `last` shows up, tells the test
// again, then waits for more inside the native watcher.
fn follow(root String, last String, move seen WriteStream[Int]) Void! {
	var events = watch(root, recursive: true, options: WatchOptions(max_events: 4096))?
	var out = seen
	out.write(0)?
	var count = 0

	while true {
		ev := events.next()
		if ev.is_error() { print(f"DBG follow next error after {count}: {ev.err().message}\n") }
		event := ev?
		found := event
		count += 1

		if found != null {
			if found.path == last {
				out.write(1)?
			}
		} else {
			print(f"DBG follow stream ended after {count}\n")
			break
		}
	}
}

// A cancelled read inside the native watcher must leave the watcher to the stream that
// owns it. The frame of `WatchSource.next` held the source it took out of the stream,
// refilled after `pending.pop()`, and unwinding dropped that copy too, so the watcher
// (and its map of watch descriptors) was freed twice.
test "cancelling a recursive watch after a burst of events releases the watcher once" {
	temp := temporary("ms-watch-cancel-") | expect_ok?
	path := temp.path()
	var ready = pipe[Int](4)
	var reader = ready.reader()
	switch := cancel_switch()
	last := f"{path}/d19"
	work := promise(() => follow(path.clone(), last.clone(), ready.writer())).with(
		options: PromiseOptions(cancel: switch.signal())
	)
	_registered := reader.next()?
	var i = 0

	while i < 20 {
		create_directory(f"{path}/d{i}/e/f", recursive: true)?
		i += 1
	}

	r2 := reader.next()
	if r2.is_error() { print(f"DBG arrived error: {r2.err().message} kind={r2.err().kind}\n") }
	_arrived := r2?
	switch.cancel()
	w := work.wait()
	print(f"DBG work after cancel error={w.is_error()}\n")
	expect_true(w.is_error())?
}
