// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	hex_decode from "@std/data/encoding.ms",
	ArchiveEntry,
	ArchiveFormat,
	ArchiveOptions,
	CompressionFormat,
	compress,
	decompress,
	pack,
	unpack from "@std/io/archive.ms",
	expect_equal, expect_error from "@std/test/test.ms",
)

test "compression formats roundtrip and enforce expanded byte budgets":
	input := "hello hello hello".to_bytes()

	for format in [
		CompressionFormat.Gzip,
		CompressionFormat.Zlib,
		CompressionFormat.Deflate,
	]:
		packed := compress(input, format)?
		expect_equal((decompress(packed, format, 17)?), input)?

		limited: Bytes! := error(
			Error("compression: limit exceeded", kind: "EOVERFLOW")
		)
		expect_equal(decompress(packed, format, 16), limited)?

	malformed: Bytes! := error(Error("compression: invalid data", kind: "EBADMSG"))
	expect_equal(decompress(input, CompressionFormat.Gzip), malformed)?

test "ZIP and TAR preserve entries and independently enforce archive limits":
	entries := [
		ArchiveEntry("a.txt", "hello".to_bytes(), directory: false),
		ArchiveEntry("b.txt", "bye".to_bytes(), directory: false),
	]

	for format in [ArchiveFormat.Zip, ArchiveFormat.Tar]:
		packed := pack(entries, format)?
		expect_equal((unpack(packed, format)?), entries)?

		limited: List[ArchiveEntry]! := error(
			Error("archive: limit exceeded", kind: "EOVERFLOW")
		)
		expect_equal(unpack(packed, format, ArchiveOptions(max_entries: 1)), limited)?
		expect_equal(
			unpack(packed, format, ArchiveOptions(max_entry_bytes: 4)),
			limited,
		)?
		expect_equal(unpack(packed, format, ArchiveOptions(max_bytes: 7)), limited)?

test "archives reject traversal paths":
	invalid: Bytes! := error(Error("archive: invalid input", kind: "EINVAL"))

	for path in ["../escape", "/absolute"]:
		entries := [ArchiveEntry(path, "".to_bytes(), directory: false)]
		expect_equal(pack(entries, ArchiveFormat.Zip), invalid)?

test "ZIP unpack verifies a zero stored checksum":
	forged := hex_decode(
		"504b03041400000000000000210000000000050000000500000005000000662e74787468656c6c6f504b0102140314000000000000002100000000000500000005000000050000000000000000000000800100000000662e747874504b0506000000000100010033000000280000000000",
		none,
	).get(Bytes([]))
	failure := expect_error(unpack(forged, ArchiveFormat.Zip))?
	expect_equal(failure.kind.get(""), "EBADMSG")?
