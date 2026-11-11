import (
	Bytes from "@std/bytes.ms",
	uuid_v4 from "@std/data/uuid.ms",
	ArchiveEntry, ArchiveFormat, pack, unpack from "@std/io/archive.ms",
	ReadStream, Source from "@std/io/io.ms",
	sse_events from "@std/net/sse.ms",
	keep, measure from "@std/test/bench.ms",
	parse_timestamp from "@std/time.ms",
)

fn entries(count: Int) List[ArchiveEntry]:
	var out: List[ArchiveEntry] = []
	for i in 0..count:
		out.append(
			ArchiveEntry(
				"dir/file{i}.txt", "contents of file {i}".to_bytes(), directory: false
			)
		)
	return out

fn sse_stream(count: Int) Bytes:
	var parts: List[String] = []
	for i in 0..count:
		parts.append("event: tick\nid: {i}\ndata: payload {i}\ndata: second line\n\n")
	return parts.join("").to_bytes()

// Hands out its bytes as one chunk.
type Whole:
	data: Bytes
	done: Bool

fn var Whole.next() Bytes?!:
	if self.done: return ok(none)

	self.done = true
	return ok(self.data.clone())

fn var Whole.close() Unit!:
	return ok(unit)

fn count_events(data: Bytes) Int:
	var events = sse_events(ReadStream[Bytes](Whole(data, false)))
	var count = 0

	while true:
		if next := events.next():
			if next.is_none(): break

			count += 1
		else:
			break

	return count

bench "archive.zip_pack":
	list := entries(2000)

	fn work() Result[Unit, Error]:
		if b := pack(list, ArchiveFormat.Zip): return keep(b.length())
		return keep(0)

	measure(2000, work)?

bench "archive.tar_pack":
	list := entries(2000)

	fn work() Result[Unit, Error]:
		if b := pack(list, ArchiveFormat.Tar): return keep(b.length())
		return keep(0)

	measure(2000, work)?

bench "archive.zip_unpack":
	if packed := pack(entries(2000), ArchiveFormat.Zip):
		fn work() Result[Unit, Error]:
			if e := unpack(packed, ArchiveFormat.Zip): return keep(e.length())
			return keep(0)

		measure(2000, work)?

bench "sse.feed":
	data := sse_stream(2000)
	fn work() Result[Unit, Error]:
		return keep(count_events(data.clone()))
	measure(2000, work)?

bench "time.timestamp_to_string":
	fn work() Result[Unit, Error]:
		var n = 0
		if t := parse_timestamp("2026-03-01T12:30:45.123Z"):
			for i in 0..20000:
				n += t.to_string().length()
		return keep(n)

	measure(20000, work)?

bench "random.uuid_v4":
	fn work() Result[Unit, Error]:
		var n = 0
		for i in 0..20000:
			if u := uuid_v4():
				n += u.length()
		return keep(n)

	measure(20000, work)?
