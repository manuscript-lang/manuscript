import (
	Bytes from "@std/bytes.ms",
	uuid_v4 from "@std/data/uuid.ms",
	ArchiveEntry, ArchiveFormat, pack, unpack from "@std/io/archive.ms",
	ReadStream, Source from "@std/io/io.ms",
	sse_events from "@std/net/sse.ms",
	parse_timestamp from "@std/time.ms",
)

fn entries(count Int) List[ArchiveEntry] {
	var out List[ArchiveEntry] = []
	for i in 0..count {
		out.append(
			ArchiveEntry(
				f"dir/file{i}.txt",
				f"contents of file {i}".to_bytes(),
				directory: false,
			)
		)
	}
	return out
}

fn sse_stream(count Int) Bytes {
	var parts List[String] = []
	for i in 0..count {
		parts.append(f"event: tick\nid: {i}\ndata: payload {i}\ndata: second line\n\n")
	}
	return parts.join("").to_bytes()
}

// Hands out its bytes as one chunk.
type Whole {
	data Bytes
	done Bool
}

fn var Whole.next() Bytes?! {
	if self.done { return ok(null) }

	self.done = true
	return ok(self.data.clone())
}

fn move Whole.close() Void! {
	return ok()
}

fn count_events(data Bytes) Int {
	var events = sse_events(ReadStream[Bytes](Whole(data.clone(), false)))
	var count = 0

	while true {
		if next := events.next() {
			if next == null { break }

			count += 1
		} else {
			break
		}
	}

	return count
}

type BenchData {
	list List[ArchiveEntry]
	list_2 List[ArchiveEntry]
	data, packed Bytes
}

fn make_fixture() BenchData {
	list := entries(2000)
	list_2 := entries(2000)
	data := sse_stream(2000)
	packed := pack(entries(2000), ArchiveFormat.Zip).get()
	return BenchData(list: list, list_2: list_2, data: data, packed: packed.clone())
}

bench "archive.zip_pack" per 2000 {
	pack(fixture.list, ArchiveFormat.Zip).get().length()
}

bench "archive.tar_pack" per 2000 {
	pack(fixture.list_2, ArchiveFormat.Tar).get().length()
}

bench "archive.zip_unpack" per 2000 {
	unpack(fixture.packed, ArchiveFormat.Zip).get().length()
}

bench "sse.feed" per 2000 {
	count_events(fixture.data.clone())
}

bench "time.timestamp_to_string" per 20000 {
	var n = 0
	if t := parse_timestamp("2026-03-01T12:30:45.123Z") {
		for i in 0..20000 {
			n += t.to_string().length()
		}
	}
	n
}

bench "random.uuid_v4" per 20000 {
	var n = 0
	for i in 0..20000 {
		if u := uuid_v4() {
			n += u.length()
		}
	}
	n
}
