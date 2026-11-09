import keep, measure from "@std/test/bench.ms"
import Bytes from "@std/bytes.ms"
import pack, unpack, ArchiveEntry, ArchiveFormat from "@std/io/archive.ms"
import sse_events from "@std/net/sse.ms"
import ReadStream, Source from "@std/io/io.ms"
import parse_timestamp from "@std/time.ms"
import uuid_v4 from "@std/data/uuid.ms"

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

impl Source[Bytes] for Whole:
    var fn next() Bytes?!:
        if self.done: return ok(none)

        self.done = true
        return ok(self.data.clone())

    var fn close() Unit!:
        return ok(unit)

fn count_events(data: Bytes) Int:
    var events = sse_events(ReadStream[Bytes](Whole(data, false)))
    var count = 0

    while true:
        if let next = events.next():
            if next.is_none(): break

            count += 1
        else:
            break

    return count

bench "archive.zip_pack":
    let list = entries(2000)

    fn work() Result[Unit, Error]:
        if let b = pack(list, ArchiveFormat.Zip):
            return keep(b.length())

        return keep(0)

    try measure(2000, work)

bench "archive.tar_pack":
    let list = entries(2000)

    fn work() Result[Unit, Error]:
        if let b = pack(list, ArchiveFormat.Tar):
            return keep(b.length())

        return keep(0)

    try measure(2000, work)

bench "archive.zip_unpack":
    if let packed = pack(entries(2000), ArchiveFormat.Zip):
        fn work() Result[Unit, Error]:
            if let e = unpack(packed, ArchiveFormat.Zip):
                return keep(e.length())

            return keep(0)

        try measure(2000, work)

bench "sse.feed":
    let data = sse_stream(2000)
    fn work() Result[Unit, Error]:
        return keep(count_events(data.clone()))
    try measure(2000, work)

bench "time.timestamp_to_string":
    fn work() Result[Unit, Error]:
        var n = 0
        if let t = parse_timestamp("2026-03-01T12:30:45.123Z"):
            for i in 0..20000:
                n += t.to_string().length()
        return keep(n)

    try measure(20000, work)

bench "random.uuid_v4":
    fn work() Result[Unit, Error]:
        var n = 0
        for i in 0..20000:
            if let u = uuid_v4():
                n += u.length()
        return keep(n)

    try measure(20000, work)
