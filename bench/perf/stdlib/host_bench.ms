import keep, measure from "@std/bench.ms"
import Bytes from "@std/bytes.ms"
import pack, unpack, ArchiveEntry from "@std/archive.ms"
import decoder, SseDecoder from "@std/sse.ms"
import parse_timestamp from "@std/time.ms"
import uuid_v4, entropy from "@std/random.ms"

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

fn feed_all(var d: SseDecoder, stream: Bytes) Int:
    if let events = d.feed(stream):
        return events.length()

    return 0

bench "archive.zip_pack":
    let list = entries(2000)

    fn work() Result[Unit, Error]:
        if let b = pack(list, "zip"):
            return keep(b.length())

        return keep(0)

    try measure(2000, work)

bench "archive.tar_pack":
    let list = entries(2000)

    fn work() Result[Unit, Error]:
        if let b = pack(list, "tar"):
            return keep(b.length())

        return keep(0)

    try measure(2000, work)

bench "archive.zip_unpack":
    if let packed = pack(entries(2000), "zip"):
        fn work() Result[Unit, Error]:
            if let e = unpack(packed, "zip"):
                return keep(e.length())

            return keep(0)

        try measure(2000, work)

bench "sse.feed":
    let stream = sse_stream(2000)

    fn work() Result[Unit, Error]:
        if let made = decoder():
            var d = made
            return keep(feed_all(var d, stream))

        return keep(0)

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
        let source = entropy()
        for i in 0..20000:
            if let u = uuid_v4(source):
                n += u.length()
        return keep(n)

    try measure(20000, work)
