import (
	uuid_v4 from "@std/data/uuid.ms",
	arguments from "@std/os/env.ms",
	OpenMode,
	OpenOptions,
	WatchOptions,
	append_file,
	open,
	read_file,
	remove,
	stat,
	watch,
	write_file from "@std/os/fs.ms",
	posix, win32 from "@std/os/path.ms",
	process_info from "@std/os/process.ms",
	memory_usage, system_info from "@std/os/system.ms",
	random_bytes, secure_int from "@std/random.ms",
	expect_equal, expect_false, expect_true from "@std/test/test.ms",
	now, parse_timestamp from "@std/time.ms",
)

fn common_result[T](result: T!) T!: result

fn exercise(path: String) Unit!:
	_written := common_result(
		result: write_file(path: path, data: "hello", replace: false).wait()
	)?
	expect_false(
		not (
			common_result(
				result: read_file(path: path, max_bytes: 5).wait()
			)? == "hello".to_bytes()
		)
	)?

	info := common_result(result: stat(path: path))?
	info.size | expect_equal(5)?
	(not info.is_directory()) | expect_true?

	bytes := common_result(result: random_bytes(count: 16))?
	bytes.length() | expect_equal(16)?

	identifier := common_result(result: uuid_v4())?
	identifier.byte_length() | expect_equal(36)?

	random := common_result(result: secure_int(min: -2, max_exclusive: 3))?
	(random >= -2 and random < 3) | expect_true?

	now := now()
	(
		(
			common_result(result: parse_timestamp(text: now.to_string()))?
		) | expect_equal(now)?
	)
	(system_info().cpu_count > 0) | expect_true?

	var file = common_result(
		result: open(path, OpenMode.ReadWrite, OpenOptions(permissions: 384))
	)?
	_updated := common_result(result: file.write_at(offset: 0, data: "HELLO"))?
	expect_false(
		not (
			common_result(
				result: file.read_at(offset: 0, max_bytes: 5)
			)? == "HELLO".to_bytes()
		)
	)?

	_synced := common_result(result: file.sync())?
	_resized := common_result(result: file.truncate(size: 3))?
	(common_result(result: file.stat())?).size | expect_equal(3)?
	file.close()?

	var watcher = common_result(
		result: watch(
			path: path,
			recursive: false,
			options: WatchOptions(
				max_entries: 4,
				max_events: 16,
				overflow: "error",
			),
		)
	)?
	_appended := common_result(result: append_file(path: path, data: "!").wait())?
	events := watcher.next()?
	events.is_some() | expect_true?
	watcher.close()?

	paths := posix()
	expect_false(
		not (
			common_result(
				result: paths.resolve(
					base: "/work",
					parts: ["a", "../b"],
				)
			)? == "/work/b"
		)
	)?

	windows := win32()
	windows.parse("C:/work/file.txt").extension | expect_equal(".txt")?

	process_info := common_result(result: process_info())?
	(process_info.pid > 0) | expect_true?

	memory := common_result(result: memory_usage())?
	(memory.heap_system > 0) | expect_true?

	_removed := common_result(result: remove(path: path, recursive: false))?

export fn main() Int:
	path := arguments().get(index: 0, default: "")
	if path == "": return 2

	match exercise(path: path):
		ok(_):
			return 0
		error(_):
			return 1
