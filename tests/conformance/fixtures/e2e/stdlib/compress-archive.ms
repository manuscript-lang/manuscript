// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Bytes, BytesBuilder from "@std/bytes.ms",
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
	).get_or(Bytes([]))
	failure := expect_error(unpack(forged, ArchiveFormat.Zip))?
	expect_equal(failure.kind.get_or(""), "EBADMSG")?

fn put_le(var out: BytesBuilder, x: Int, width: Int) Void:
	var rest = x

	for i in 0..width:
		out.append((rest % 256).to_uint8().get_or(0))
		rest /= 256

fn le_at(b: Bytes, at: Int, width: Int) Int:
	var x = 0
	for i in 0..width:
		x = x * 256 + b.get(at + width - 1 - i).to_int()
	return x

// A one-member archive whose ZIP64 end record carries the real count, size and offset,
// and whose legacy end fields chosen by `mask` (1 count, 2 size, 4 offset) hold
// sentinels.
fn with_zip64_end(mask: Int) Bytes:
	entry := ArchiveEntry("a.txt", "zip64 size sentinel".to_bytes(), directory: false)
	plain := pack([entry], ArchiveFormat.Zip).get_or(Bytes([]))
	end_at := plain.length() - 22
	count := le_at(plain, end_at + 10, 2)
	size := le_at(plain, end_at + 12, 4)
	offset := le_at(plain, end_at + 16, 4)
	var out = BytesBuilder()
	out.append_bytes(plain.view(0, end_at))
	put_le(out, 101075792, 4)
	put_le(out, 44, 8)
	put_le(out, 45, 2)
	put_le(out, 45, 2)
	put_le(out, 0, 8)
	for v in [count, count, size, offset]:
		put_le(out, v, 8)
	put_le(out, 117853008, 4)
	put_le(out, 0, 4)
	put_le(out, end_at, 8)
	put_le(out, 1, 4)

	for i in 0..22:
		var byte = plain.get(end_at + i)
		if i >= 8 and i < 12 and mask % 2 == 1: byte = 255
		if i >= 12 and i < 16 and mask / 2 % 2 == 1: byte = 255
		if i >= 16 and i < 20 and mask / 4 % 2 == 1: byte = 255
		out.append(byte)

	return out.build()

test "ZIP64 end record sentinels trigger independently":
	for mask in 1..8:
		files := unpack(with_zip64_end(mask), ArchiveFormat.Zip)?
		expect_equal(files.length(), 1)?
		expect_equal(files.get(0).data, "zip64 size sentinel".to_bytes())?

	limited: List[ArchiveEntry]! := error(
		Error("archive: limit exceeded", kind: "EOVERFLOW")
	)
	expect_equal(
		unpack(
			with_zip64_end(2),
			ArchiveFormat.Zip,
			ArchiveOptions(max_entry_bytes: 1),
		),
		limited,
	)?

test "tar unpack rejects a damaged header checksum":
	listed := pack(
		[
			ArchiveEntry("d", "".to_bytes(), directory: true),
			ArchiveEntry("d/f", "x".to_bytes(), directory: false),
		],
		ArchiveFormat.Tar,
	)?
	var damaged = BytesBuilder()

	for i in 0..listed.length():
		var byte = listed.get(i)
		if i == 148: byte = 0x39
		damaged.append(byte)

	invalid: List[ArchiveEntry]! := error(
		Error("archive: invalid data", kind: "EBADMSG")
	)
	expect_equal(unpack(damaged.build(), ArchiveFormat.Tar), invalid)?
