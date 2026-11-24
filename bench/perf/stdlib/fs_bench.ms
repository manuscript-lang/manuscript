import (
	Bytes from "@std/bytes.ms",
	Logger, LoggerOptions, create, file_transport from "@std/log.ms",
	list, read_file, remove, stat, temporary_directory, write_file from "@std/os/fs.ms",
)

fn block() Bytes:
	return "0123456789abcdef".repeat(4096).to_bytes()

// The directory holds the 200 files that the read, stat, and list cases use; `scratch`
// is a second directory that the write case overwrites into.
type BenchData:
	root String
	scratch String
	data Bytes
	logger Logger
	scratch_files List[String]
	files List[String]

fn make_fixture() BenchData:
	root := temporary_directory("ms-bench-").get()
	scratch := temporary_directory("ms-bench-").get()
	data := block()
	var files List[String] = []
	var scratch_files List[String] = []

	for i in 0..200:
		path := f"{root}/f{i}.bin"
		write_file(path, data, replace: true).wait().get()
		files.append(path)
		scratch_files.append(f"{scratch}/f{i}.bin")

	return BenchData(
		logger: create(
			file_transport(f"{root}/log.txt").get(),
			LoggerOptions(timestamp: false),
		).get(),
		root: root.clone(),
		scratch: scratch.clone(),
		data: data,
		scratch_files: scratch_files,
		files: files,
	)

fn var BenchData.after_all() Void!:
	remove(self.root, recursive: true)?
	remove(self.scratch, recursive: true)?

bench "fs.write_file_64k" per 200:
	var n = 0
	for path in fixture.scratch_files:
		if write_file(path, fixture.data, replace: true).wait().is_ok():
			n += 1
	n

bench "fs.read_file_64k" per 200:
	var n = 0
	for path in fixture.files:
		if b := read_file(path).wait():
			n += b.length()
	n

bench "fs.stat" per 200:
	var n = 0
	for path in fixture.files:
		if stat(path, follow_links: true).is_ok():
			n += 1
	n

bench "fs.list_200":
	entries := list(fixture.root)?
	entries.length()

bench "log.info" per 20000:
	var n = 0
	for i in 0..20000:
		if fixture.logger.info(f"request {i} handled").is_ok():
			n += 1
	n
