import (
	ReadStream from "@std/io/io.ms",
	FileEvent,
	WatchOptions,
	temporary,
	watch,
	write_file from "@std/os/fs.ms",
	join from "@std/os/path.ms",
	milliseconds from "@std/time.ms",
	within from "./conn.ms",
)

fn show(var events: ReadStream[FileEvent], label: String) Void!:
	for attempt in 0..4:
		next := within(events, 2.seconds())?
		if event := next:
			print(f"{label} event path={event.path} kind={event.kind}")
		else:
			print(f"{label} none")
			return ok()

fn main() Int:
	t := temporary("manuscript-watch-").get()
	root := t.path()
	print(f"root={root} join={join([root.clone(), "a.txt"])}")
	var polling = watch(path: root, recursive: false, options: WatchOptions(interval: milliseconds(20))).get()
	void write_file(path: f"{root}/a.txt", data: "x", replace: false).wait()
	void show(polling, "polling")
	return 0
