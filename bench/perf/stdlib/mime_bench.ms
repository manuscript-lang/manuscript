import (
	Bytes from "@std/bytes.ms",
	from_bytes from "@std/io/streams.ms",
	Part, encode_multipart, form_part, multipart_parts from "@std/net/mime.ms",
)

// The input is built by the fixture; each operation includes the source's owned body
// copy.
fn consume(body: Bytes, chunk: Int, count: Int, size: Int) Int!:
	var parts = multipart_parts(from_bytes(body.clone(), chunk), "XyZ", null)
	var seen = 0
	var bytes = 0

	while true:
		next := parts.next()?
		part := next

		if part != null:
			if part.data.length() != size: return error(Error("wrong multipart size"))

			seen += 1
			bytes += part.data.length()
		else:
			break

	if seen != count: return error(Error("wrong multipart count"))

	return ok(bytes)

fn body(size: Int, count: Int = 1) Bytes:
	payload := "x".repeat(size).to_bytes()
	var parts: List[Part] = []
	for unused in 0..count:
		parts.append(form_part("field", payload.clone()))
	return encode_multipart(parts, "XyZ")

type BenchData:
	data: Bytes
	data_2: Bytes
	data_3: Bytes
	data_4: Bytes
	data_5: Bytes
	data_6: Bytes

fn make_fixture() BenchData:
	data := body(1048576)
	data_2 := body(4194304)
	data_3 := body(4194304)
	data_4 := body(128)
	data_5 := body(65536)
	data_6 := body(128, 100)
	return BenchData(
		data: data,
		data_2: data_2,
		data_3: data_3,
		data_4: data_4,
		data_5: data_5,
		data_6: data_6,
	)

bench "multipart.fragmented_1MiB_1KiB_chunks":
	consume(fixture.data, 1024, 1, 1048576)?

bench "multipart.fragmented_4MiB_1KiB_chunks":
	consume(fixture.data_2, 1024, 1, 4194304)?

bench "multipart.4MiB_default_64KiB_chunks":
	consume(fixture.data_3, 65536, 1, 4194304)?

bench "multipart.small_128B_single_chunk":
	consume(fixture.data_4, 65536, 1, 128)?

bench "multipart.64KiB_single_chunk":
	consume(fixture.data_5, 1048576, 1, 65536)?

bench "multipart.100_small_parts_single_chunk":
	consume(fixture.data_6, 65536, 100, 128)?

bench "multipart.fragmented_limit_rejection":
	var parts = multipart_parts(from_bytes(fixture.data_5.clone(), 1024), "XyZ", 4096)
	if parts.next().err().kind != "EOVERFLOW": return error(
		Error("wrong multipart error")
	)

	1
