import (
	Bytes from "@std/bytes.ms",
	CompressOptions, CompressionFormat, compress, decompress from "@std/io/archive.ms",
	OpenMode, OpenOptions, Seek, open, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_error, expect_false from "@std/test/test.ms",
)

test "closed normalization forms reject spelling changes with their domain errors":
	data := "text".to_bytes()
	normalization_error: String! := error(
		Error("string: invalid input", kind: "EINVAL")
	)
	for form in ["nfc", "NFC ", ""]:
		try expect_equal("text".normalize(form), normalization_error)
	for form in ["NFC", "NFD", "NFKC", "NFKD"]:
		try expect_equal((try "text".normalize(form)), "text")
	for format in [
		CompressionFormat.Gzip, CompressionFormat.Zlib, CompressionFormat.Deflate
	]:
		for level in [0, 9]:
			try expect_equal(
				(
					try compress(
						data, format, CompressOptions(level: level)
					) | try decompress(format)
				),
				data
			)

	level_error: Bytes! := error(Error("compression: invalid input", kind: "EINVAL"))
	for level in [-1, 10]:
		try expect_equal(
			compress(
				data, CompressionFormat.Gzip, CompressOptions(level: level)
			),
			level_error
		)

test "every open mode with and without exclusive creation opens":
	temporary := try temporary("manuscript-open-modes-")
	modes := [
		OpenMode.Read, OpenMode.ReadWrite, OpenMode.Write, OpenMode.WriteRead,
		OpenMode.Append, OpenMode.AppendRead
	]

	for index in 0..modes.length():
		mode := modes[index]
		path := "{temporary.path()}/{index}"
		if index < 2:
			try write_file(path, "", replace: false).wait()

		handle := try open(path, mode, OpenOptions(permissions: 384))
		_fileinfo := try handle.stat()

	// Exclusive creation fails on an existing file and succeeds on a new one.
	existing := "{temporary.path()}/2"
	refused := try expect_error(
		open(existing, OpenMode.Write, OpenOptions(exclusive: true))
	)
	try expect_equal(refused.kind, "EEXIST")

	fresh := try open(
		"{temporary.path()}/fresh", OpenMode.AppendRead, OpenOptions(exclusive: true)
	)
	_fresh_info := try fresh.stat()

test "full byte counts positions EOF and stream aliases retain their contracts":
	temporary := try temporary("manuscript-write-contract-")
	path := "{temporary.path()}/data"
	data := (try "é".repeat(40000)).to_bytes()
	var handle = try open(path, OpenMode.WriteRead, OpenOptions(permissions: 384))
	try handle.write(data)
	try expect_equal((try handle.stat()).size, 80000)
	try expect_false((try handle.read()).is_some())
	try expect_equal((try handle.read_at(80000)).length(), 0)
	try expect_equal((try handle.read_at(0, 80000)).length(), 65536)
	try expect_equal((try handle.read_file()).length(), 0)
	try expect_equal((try handle.seek(0, Seek.Start)), 0)
	try expect_equal((try handle.read()).get().length(), 65536)
	try expect_equal((try handle.read_file()).length(), 14464)

	_count := try handle.seek(0, Seek.Start)
	try handle.write("XY")
	try expect_equal((try handle.read_at(0, 2)), "XY".to_bytes())
	try expect_equal((try handle.stat()).size, 80000)
	try handle.write_at(4, "ZZ")
	try expect_equal((try handle.seek(0, Seek.Current)), 2)

	var writer = try handle.writer()
	try writer.write("AB".to_bytes())
	try writer.flush()
	try expect_equal((try handle.read_at(2, 4)), "ABZZ".to_bytes())

	var reader = try handle.reader()
	try writer.close()
	try expect_equal((try handle.read_at(2, 4)), "ABZZ".to_bytes())
	try handle.close()

	closed_read: Bytes! := error(Error("filesystem: resource is closed", kind: "EBADF"))
	try expect_equal(handle.read_at(0), closed_read)
	try reader.close()

	missing := "{temporary.path()}/missing"
	absent := try expect_error(
		open(missing, OpenMode.Read, OpenOptions(permissions: 384))
	)
	try expect_equal(absent.kind, "ENOENT")
	try expect_equal(
		absent.message, "filesystem: file or directory not found: {missing}"
	)
