import (
	Bytes from "@std/bytes.ms",
	from_bytes from "@std/io/streams.ms",
	Part, encode_multipart, form_part, multipart_parts from "@std/net/mime.ms",
	keep, measure from "@std/test/bench.ms",
)

// Input construction is outside measure; each operation includes the source's owned body copy.
fn consume(body: Bytes, chunk: Int, count: Int, size: Int) Unit!:
	var parts = multipart_parts(from_bytes(body.clone(), chunk), "XyZ", none)
	var seen = 0
	var bytes = 0

	while true:
		next := parts.next()?

		if part := next:
			if part.data.length() != size: return error(Error("wrong multipart size"))

			seen += 1
			bytes += part.data.length()
		else:
			break

	if seen != count: return error(Error("wrong multipart count"))

	return keep(bytes)

fn body(size: Int, count: Int = 1) Bytes:
	payload := "x".repeat(size).get().to_bytes()
	var parts: List[Part] = []
	for unused in 0..count:
		parts.append(form_part("field", payload.clone()))
	return encode_multipart(parts, "XyZ")

bench "multipart.fragmented_1MiB_1KiB_chunks":
	data := body(1048576)
	measure(1, fn: consume(data, 1024, 1, 1048576))?

bench "multipart.fragmented_4MiB_1KiB_chunks":
	data := body(4194304)
	measure(1, fn: consume(data, 1024, 1, 4194304))?

bench "multipart.4MiB_default_64KiB_chunks":
	data := body(4194304)
	measure(1, fn: consume(data, 65536, 1, 4194304))?

bench "multipart.small_128B_single_chunk":
	data := body(128)
	measure(1, fn: consume(data, 65536, 1, 128))?

bench "multipart.64KiB_single_chunk":
	data := body(65536)
	measure(1, fn: consume(data, 1048576, 1, 65536))?

bench "multipart.100_small_parts_single_chunk":
	data := body(128, 100)
	measure(1, fn: consume(data, 65536, 100, 128))?

bench "multipart.fragmented_limit_rejection":
	data := body(65536)

	fn reject() Unit!:
		var parts = multipart_parts(from_bytes(data.clone(), 1024), "XyZ", 4096)
		if parts.next().err().kind != "EOVERFLOW": return error(
			Error("wrong multipart error")
		)

		return keep(1)

	measure(1, reject)?
