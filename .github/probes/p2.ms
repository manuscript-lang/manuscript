import (
	create_directory, temporary, watch, write_file from "@std/os/fs.ms",
	join from "@std/os/path.ms",
	hold_stop, watch_signals from "@std/os/process.ms",
)

fn main() Void:
	_hold := hold_stop()
	signals := watch_signals([2, 15], none)
	print(f"probe 2: signals {signals.is_ok()}")

	dir := temporary("probe-")

	if dir.is_error():
		print("probe 2: no temp")
		return

	holder := dir.get()
	path := holder.path()
	var watcher = watch(path)
	print(f"probe 3: watch {watcher.is_ok()}")
	if watcher.is_error(): return

	void write_file(join([path.clone(), "f"]), "x").wait()

	event := watcher.get().next()
	print(f"probe 3: event {event.is_ok()}")
