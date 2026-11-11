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
		expect_equal("text".normalize(form), normalization_error)?
	for form in ["NFC", "NFD", "NFKC", "NFKD"]:
		expect_equal(("text".normalize(form)?), "text")?
	for format in [
		CompressionFormat.Gzip, CompressionFormat.Zlib, CompressionFormat.Deflate
	]:
		for level in [0, 9]:
			expect_equal(
				(
					compress(
						data, format, CompressOptions(level: level)
					)? | decompress(format)?
				),
				data
			)?

	level_error: Bytes! := error(Error("compression: invalid input", kind: "EINVAL"))
	for level in [-1, 10]:
		expect_equal(
			compress(
				data, CompressionFormat.Gzip, CompressOptions(level: level)
			),
			level_error
		)?

test "every open mode with and without exclusive creation opens":
	temporary := temporary("manuscript-open-modes-")?
	modes := [
		OpenMode.Read, OpenMode.ReadWrite, OpenMode.Write, OpenMode.WriteRead,
		OpenMode.Append, OpenMode.AppendRead
	]

	for index in 0..modes.length():
		mode := modes[index]
		path := "{temporary.path()}/{index}"
		if index < 2:
			write_file(path, "", replace: false).wait()?

		handle := open(path, mode, OpenOptions(permissions: 384))?
		_fileinfo := handle.stat()?

	// Exclusive creation fails on an existing file and succeeds on a new one.
	existing := "{temporary.path()}/2"
	refused := expect_error(
		open(existing, OpenMode.Write, OpenOptions(exclusive: true))
	)?
	expect_equal(refused.kind, "EEXIST")?

	fresh := open(
		"{temporary.path()}/fresh", OpenMode.AppendRead, OpenOptions(exclusive: true)
	)?
	_fresh_info := fresh.stat()?

test "full byte counts positions EOF and stream aliases retain their contracts":
	temporary := temporary("manuscript-write-contract-")?
	path := "{temporary.path()}/data"
	data := ("é".repeat(40000)?).to_bytes()
	var handle = open(path, OpenMode.WriteRead, OpenOptions(permissions: 384))?
	handle.write(data)?
	expect_equal((handle.stat()?).size, 80000)?
	expect_false((handle.read()?).is_some())?
	expect_equal((handle.read_at(80000)?).length(), 0)?
	expect_equal((handle.read_at(0, 80000)?).length(), 65536)?
	expect_equal((handle.read_file()?).length(), 0)?
	expect_equal((handle.seek(0, Seek.Start)?), 0)?
	expect_equal((handle.read()?).get().length(), 65536)?
	expect_equal((handle.read_file()?).length(), 14464)?

	_count := handle.seek(0, Seek.Start)?
	handle.write("XY")?
	expect_equal((handle.read_at(0, 2)?), "XY".to_bytes())?
	expect_equal((handle.stat()?).size, 80000)?
	handle.write_at(4, "ZZ")?
	expect_equal((handle.seek(0, Seek.Current)?), 2)?

	var writer = handle.writer()?
	writer.write("AB".to_bytes())?
	writer.flush()?
	expect_equal((handle.read_at(2, 4)?), "ABZZ".to_bytes())?

	var reader = handle.reader()?
	writer.close()?
	expect_equal((handle.read_at(2, 4)?), "ABZZ".to_bytes())?
	handle.close()?

	closed_read: Bytes! := error(Error("filesystem: resource is closed", kind: "EBADF"))
	expect_equal(handle.read_at(0), closed_read)?
	reader.close()?

	missing := "{temporary.path()}/missing"
	absent := expect_error(open(missing, OpenMode.Read, OpenOptions(permissions: 384)))?
	expect_equal(absent.kind, "ENOENT")?
	expect_equal(absent.message, "filesystem: file or directory not found: {missing}")?
