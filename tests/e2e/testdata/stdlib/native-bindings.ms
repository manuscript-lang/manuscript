import (
	PromiseOptions from "@std/concurrency/promise.ms",
	ReadStream from "@std/io/io.ms",
	FileEvent,
	WatchOptions,
	create_directory,
	stat_filesystem,
	temporary,
	watch,
	write_file from "@std/os/fs.ms",
	join from "@std/os/path.ms",
	IdentityKind,
	cpu_usage,
	groups,
	process_info,
	replace,
	resource_usage,
	set_groups,
	set_identity from "@std/os/process.ms",
	memory_usage from "@std/os/system.ms",
	expect_false, expect_ok, expect_true from "@std/test/test.ms",
	milliseconds from "@std/time.ms",

	within from "./support/conn.ms",
)

fn expect_process_error[T](outcome: T!, expected: Error) Unit!:
	match outcome:
		ok(_): return error(Error("process misuse succeeded"))
		error(cause):
			if cause.kind != expected.kind: return error(Error("wrong process error"))

fn expect_fs_error[T](outcome: T!, expected: Error) Unit!:
	match outcome:
		ok(_): return error(Error("filesystem misuse succeeded"))
		error(cause):
			if cause.kind != expected.kind: return error(
				Error("wrong filesystem error")
			)

test "process usage records report this process":
	cpu := cpu_usage()?
	expect_false(cpu.user_microseconds < 0 or cpu.system_microseconds < 0)?

	resources := resource_usage()?
	expect_false(resources.max_resident_bytes <= 0)?
	expect_false(resources.user_microseconds < 0 or resources.involuntary_switches < 0)?

	memory := memory_usage()?
	expect_false(memory.heap_used <= 0 or memory.resident <= 0)?
	expect_false(memory.heap_total < memory.heap_used)?

test "set_identity and set_groups validate input and apply or refuse":
	expect_process_error(
		set_identity(kind: IdentityKind.Uid, id: -1),
		Error("process: invalid input", kind: "EINVAL"),
	)?
	expect_process_error(
		set_groups(groups: [-1]),
		Error("process: invalid input", kind: "EINVAL"),
	)?

	info := process_info()?

	if info.uid < 0:
		// Windows has no ids.
		expect_process_error(
			set_identity(kind: IdentityKind.Uid, id: 0),
			Error("process: operation not supported", kind: "ENOTSUP"),
		)?
		expect_process_error(
			set_groups(groups: [0]),
			Error("process: operation not supported", kind: "ENOTSUP"),
		)?
	else:
		// Setting the identity it already has changes nothing and needs no privilege.
		set_identity(kind: IdentityKind.Uid, id: info.uid)?
		set_identity(kind: IdentityKind.Gid, id: info.gid)?
		set_identity(kind: IdentityKind.Euid, id: info.effective_uid)?
		set_identity(kind: IdentityKind.Egid, id: info.effective_gid)?

		groups := groups()?

		if info.effective_uid == 0:
			set_groups(groups: groups)?
		else:
			expect_process_error(
				set_groups(groups: groups),
				Error("process: permission denied", kind: "EACCES"),
			)?

test "replace rejects invalid programs before leaving this process":
	info := process_info()?
	empty := replace(program: "", arguments: ["x"], environment: {})
	missing := replace(
		program: "/definitely/not/a/program",
		arguments: ["x"],
		environment: {},
	)

	if info.uid < 0:
		// Windows has no exec.
		expect_process_error(
			empty,
			Error("process: operation not supported", kind: "ENOTSUP"),
		)?
		expect_process_error(
			missing,
			Error("process: operation not supported", kind: "ENOTSUP"),
		)?
	else:
		expect_process_error(empty, Error("process: invalid input", kind: "EINVAL"))?
		expect_process_error(missing, Error("process: not found", kind: "ENOENT"))?

test "stat_filesystem describes the filesystem under a path":
	info := stat_filesystem(path: ".")?
	expect_false(info.block_size <= 0 or info.blocks <= 0)?
	expect_false(info.blocks_available > info.blocks_free)?
	expect_fs_error(
		stat_filesystem(path: "/definitely/not/a/path"),
		Error("filesystem: file or directory not found", kind: "ENOENT"),
	)?

// Reads events until one has `path` and `kind`, or `tries` events passed.
fn saw(var events: ReadStream[FileEvent], path: String, kind: String, tries: Int) Bool!:
	for attempt in 0..tries:
		next := within(var events, 2.seconds())?

		if event := next:
			if event.path == path and event.kind == kind: return ok(true)
		else:
			return ok(false)

	return ok(false)

test "polling and native watchers report a created file and close":
	temporary := temporary("manuscript-watch-") | expect_ok?
	root := temporary.path()
	var polling = watch(
		path: root,
		recursive: false,
		options: WatchOptions(interval: milliseconds(20)),
	)?
	write_file(path: "{root}/a.txt", data: "x", replace: false).wait()?
	expect_true(saw(var polling, join([root.clone(), "a.txt"]), "rename", 8)?)?
	polling.close()?

	var native = watch(path: root, recursive: false)?
	write_file(path: "{root}/b.txt", data: "y", replace: false).wait()?
	expect_true(saw(var native, join([root.clone(), "b.txt"]), "rename", 8)?)?

test "native watcher max_entries counts the paths under the root":
	t := temporary("ms-me-") | expect_ok?
	write_file(path: "{t.path()}/a", data: "x", replace: false).wait()?
	expect_fs_error(
		watch(
			path: t.path(),
			recursive: true,
			options: WatchOptions(max_entries: 1),
		),
		Error("filesystem: limit exceeded", kind: "EOVERFLOW"),
	)?

	var w = watch(
		path: t.path(),
		recursive: true,
		options: WatchOptions(max_entries: 2),
	)?
	w.close()?

test "polling options reject native-only settings":
	t := temporary("ms-wo-") | expect_ok?
	polled := WatchOptions(interval: milliseconds(20))
	expect_fs_error(
		watch(
			path: t.path(),
			options: WatchOptions(interval: milliseconds(20), max_events: 4),
		),
		Error("filesystem: invalid input", kind: "EINVAL"),
	)?
	expect_fs_error(
		watch(
			path: t.path(),
			options: WatchOptions(
				interval: milliseconds(20),
				overflow: "ignore",
			),
		),
		Error("filesystem: invalid input", kind: "EINVAL"),
	)?
	expect_fs_error(
		watch(path: t.path(), options: WatchOptions(overflow: "bogus")),
		Error("filesystem: invalid input", kind: "EINVAL"),
	)?

	var w = watch(path: t.path(), options: polled)?
	w.close()?

test "recursive native watch sees a file in a new subdirectory":
	t := temporary("ms-r2-") | expect_ok?
	r := t.path()
	var w = watch(path: r, recursive: true)?
	create_directory(path: "{r}/d", recursive: false)?
	write_file(path: "{r}/d/f", data: "1", replace: false).wait()?

	var seen = false
	for i in 0..8:
		if not seen:
			if e := within(var w, 2.seconds())?:
				if e.path == join([r.clone(), "d", "f"]): seen = true
	expect_true(seen)?
