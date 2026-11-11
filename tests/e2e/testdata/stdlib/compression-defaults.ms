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
		CompressionFormat.Gzip, CompressionFormat.Zlib, CompressionFormat.Deflate
	]:
		expected := try compress(data, format, CompressOptions(level: 6))
		try expect_equal((try compress(data, format)), expected)
		try expect_equal((try compress(data, format, CompressOptions())), expected)
		try expect_equal(
			(
				try compress(
					data, format, CompressOptions(max_bytes: expected.length())
				)
			),
			expected
		)
		try expect_equal((try decompress(expected, format)), data)

		for level in [0, 9]:
			output := try compress(data, format, CompressOptions(level: level))
			try expect_equal((try decompress(output, format)), data)

		encode := compress
		try expect_equal((try encode(data, format, CompressOptions())), expected)

test "compression defaults retain invalid levels and output budgets":
	data := "abc".to_bytes()
	invalid: Bytes! := error(Error("compression: invalid input", kind: "EINVAL"))
	limited: Bytes! := error(Error("compression: limit exceeded", kind: "EOVERFLOW"))

	for format in [
		CompressionFormat.Gzip, CompressionFormat.Zlib, CompressionFormat.Deflate
	]:
		try expect_equal(compress(data, format, CompressOptions(level: -1)), invalid)
		try expect_equal(compress(data, format, CompressOptions(level: 10)), invalid)
		try expect_equal(
			compress(data, format, CompressOptions(max_bytes: -1)), invalid
		)
		try expect_equal(compress(data, format, CompressOptions(max_bytes: 0)), limited)

test "compression default preparation retains supplied argument order":
	var log: List[String] = []
	data := "data".to_bytes()
	encoded := try compress(
		format: chosen(var log, CompressionFormat.Gzip),
		data: supplied(var log, data.clone())
	)
	try expect_equal(log, ["format", "data"])
	try expect_equal((try decompress(encoded, CompressionFormat.Gzip)), data)
