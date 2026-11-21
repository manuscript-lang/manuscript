import (
	promise from "@std/concurrency/promise.ms",
	ReadStream from "@std/io/io.ms",
	FileEvent, temporary, watch, write_file from "@std/os/fs.ms",
	join from "@std/os/path.ms",
)

fn first(var events: ReadStream[FileEvent]) Int!:
	event := events.next()?
	return ok(if event.is_some(): 1 else: 0)

fn main() Void:
	dir := temporary("probe-")
	if dir.is_error(): return

	holder := dir.get()
	path := holder.path()
	made := watch(path)
	if made.is_error(): return

	var events = made.get()
	pending := promise(fn: first(events))
	void write_file(join([path.clone(), "f"]), "x").wait()

	done := pending.wait()
	print(f"probe 6: promise watch {done.is_ok()}")
