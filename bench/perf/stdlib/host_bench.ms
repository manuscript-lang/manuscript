from "@std/bench.ms" import keep, measure
from "@std/collections.ms" import range
from "@std/bytes.ms" import Bytes
from "@std/archive.ms" import pack, unpack, ArchiveEntry
from "@std/sse.ms" import decoder, SseDecoder
from "@std/time.ms" import parse_timestamp
from "@std/random.ms" import uuid_v4, entropy

def entries(count: Int) -> List[ArchiveEntry]:
    var out: List[ArchiveEntry] = []
    for i in range(0, count):
        out.append(
            ArchiveEntry(
                f"dir/file{i}.txt", f"contents of file {i}".to_bytes(), directory: False
            )
        )
    return out

def sse_stream(count: Int) -> Bytes:
    var parts: List[String] = []
    for i in range(0, count):
        parts.append(f"event: tick\nid: {i}\ndata: payload {i}\ndata: second line\n\n")
    return parts.join("").to_bytes()

def feed_all(var d: SseDecoder, stream: Bytes) -> Int:
    if let events = d.feed(stream):
        return events.length()

    return 0

bench "archive.zip_pack":
    let list = entries(2000)

    def work() -> Result[Unit, Error]:
        if let b = pack(list, "zip"):
            return keep(b.length())

        return keep(0)

    try measure(2000, work)

bench "archive.tar_pack":
    let list = entries(2000)

    def work() -> Result[Unit, Error]:
        if let b = pack(list, "tar"):
            return keep(b.length())

        return keep(0)

    try measure(2000, work)

bench "archive.zip_unpack":
    if let packed = pack(entries(2000), "zip"):
        def work() -> Result[Unit, Error]:
            if let e = unpack(packed, "zip"):
                return keep(e.length())

            return keep(0)

        try measure(2000, work)

bench "sse.feed":
    let stream = sse_stream(2000)

    def work() -> Result[Unit, Error]:
        if let made = decoder():
            var d = made
            return keep(feed_all(var d, stream))

        return keep(0)

    try measure(2000, work)

bench "time.timestamp_to_string":
    def work() -> Result[Unit, Error]:
        var n = 0
        if let t = parse_timestamp("2026-03-01T12:30:45.123Z"):
            for i in range(0, 20000):
                n += t.to_string().length()
        return keep(n)

    try measure(20000, work)

bench "random.uuid_v4":
    def work() -> Result[Unit, Error]:
        var n = 0
        let source = entropy()
        for i in range(0, 20000):
            if let u = uuid_v4(source):
                n += u.length()
        return keep(n)

    try measure(20000, work)
