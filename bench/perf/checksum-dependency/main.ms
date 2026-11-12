import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	Adler32, Crc32, adler32, crc32 from "@std/data/checksum.ms",
	arguments from "@std/os/env.ms",
	monotonic from "@std/time.ms",
)

fn crc_chunks(data: Bytes, seed: UInt32, chunk: Int) UInt32:
	var sum = Crc32(state: seed)
	var at = 0

	while at < data.length():
		end := if at + chunk < data.length(): at + chunk else: data.length()
		sum.update(data.view(at, end))
		at = end

	sum.update(data.view(0, 0))
	return sum.value()

fn adler_chunks(data: Bytes, seed: UInt32, chunk: Int) UInt32:
	var sum = Adler32(state: seed)
	var at = 0

	while at < data.length():
		end := if at + chunk < data.length(): at + chunk else: data.length()
		sum.update(data.view(at, end))
		at = end

	sum.update(data.view(0, 0))
	return sum.value()

fn measure(action: fn() UInt32, expected: UInt32, count: Int) Unit!:
	for unused in 0..100:
		if action() != expected: return error(Error("warm output"))

	var checksum = 0
	start := monotonic()

	for unused in 0..count:
		out := action()
		if out != expected: return error(Error("complete checksum output"))

		checksum += out.to_int()

	elapsed := monotonic().difference(start).to_nanoseconds()
	print("{elapsed} {checksum} {expected}")

fn main() Unit!:
	args := arguments()
	alg := args[0]
	n := args[1].parse_int().get()
	chunk := args[2].parse_int().get()
	seed := args[3].parse_int().get().to_uint32().get()
	count := args[4].parse_int().get()
	expected := args[5].parse_int().get().to_uint32().get()
	var builder = BytesBuilder()
	for i in 0..n:
		builder.append(((i * 73 + i / 7 + seed.to_int()) % 256).to_uint8().get())

	data := builder.build()

	if alg == "crc":
		if chunk == 0:
			measure(fn: crc32(data), expected, count)?
		else:
			measure(fn: crc_chunks(data, seed, chunk), expected, count)?
	else:
		if chunk == 0:
			measure(fn: adler32(data), expected, count)?
		else:
			measure(fn: adler_chunks(data, seed, chunk), expected, count)?
