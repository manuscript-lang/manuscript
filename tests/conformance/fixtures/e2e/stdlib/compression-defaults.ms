// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	CompressOptions, CompressionFormat, compress, decompress from "@std/io/archive.ms",
	expect_equal from "@std/test/test.ms",
)

fn supplied(var log: List[String], data: Bytes) Bytes:
	log.append("data")
	return data

fn chosen(var log: List[String], format: CompressionFormat) CompressionFormat:
	log.append("format")
	return format

test "compression omission equals explicit level six for every format":
	data := "repeat repeat repeat repeat".to_bytes()

	for format in [
		CompressionFormat.Gzip,
		CompressionFormat.Zlib,
		CompressionFormat.Deflate,
	]:
		expected := compress(data, format, CompressOptions(level: 6))?
		expect_equal((compress(data, format)?), expected)?
		expect_equal((compress(data, format, CompressOptions())?), expected)?
		expect_equal(
			(
				compress(
					data,
					format,
					CompressOptions(max_bytes: expected.length()),
				)?
			),
			expected,
		)?
		expect_equal((decompress(expected, format)?), data)?

		for level in [0, 9]:
			output := compress(data, format, CompressOptions(level: level))?
			expect_equal((decompress(output, format)?), data)?

		encode := compress
		expect_equal((encode(data, format, CompressOptions())?), expected)?

test "compression defaults retain invalid levels and output budgets":
	data := "abc".to_bytes()
	invalid: Bytes! := error(Error("compression: invalid input", kind: "EINVAL"))
	limited: Bytes! := error(Error("compression: limit exceeded", kind: "EOVERFLOW"))

	for format in [
		CompressionFormat.Gzip,
		CompressionFormat.Zlib,
		CompressionFormat.Deflate,
	]:
		expect_equal(compress(data, format, CompressOptions(level: -1)), invalid)?
		expect_equal(compress(data, format, CompressOptions(level: 10)), invalid)?
		expect_equal(compress(data, format, CompressOptions(max_bytes: -1)), invalid)?
		expect_equal(compress(data, format, CompressOptions(max_bytes: 0)), limited)?

test "compression default preparation retains supplied argument order":
	var log: List[String] = []
	data := "data".to_bytes()
	encoded := compress(
		format: chosen(var log, CompressionFormat.Gzip),
		data: supplied(var log, data.clone()),
	)?
	expect_equal(log, ["format", "data"])?
	expect_equal((decompress(encoded, CompressionFormat.Gzip)?), data)?
