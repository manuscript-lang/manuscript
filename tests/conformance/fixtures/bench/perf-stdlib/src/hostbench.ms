from "./harness.ms" import bench
from "@std/bytes.ms" import Bytes
from "@std/archive.ms" import pack, unpack, ArchiveEntry
from "@std/sse.ms" import decoder, SseDecoder
from "@std/time.ms" import parse_timestamp
from "@std/random.ms" import uuid_v4, entropy

def entries(count: Int) -> List[ArchiveEntry]:
    var out: List[ArchiveEntry] = []
    for i in 0..count:
        out.append(
            ArchiveEntry(
                f"dir/file{i}.txt", f"contents of file {i}".to_bytes(), directory: False
            )
        )
    return out

def sse_stream(count: Int) -> Bytes:
    var parts: List[String] = []
    for i in 0..count:
        parts.append(f"event: tick\nid: {i}\ndata: payload {i}\ndata: second line\n\n")
    return parts.join("").to_bytes()

def bench_archive() -> Unit:
    let list = entries(2000)

    bench(
        "archive.zip_pack",
        2000,
        lambda () -> Int:
            if let b = pack(list, "zip"):
                return b.length()

            return 0
    )

    bench(
        "archive.tar_pack",
        2000,
        lambda () -> Int:
            if let b = pack(list, "tar"):
                return b.length()

            return 0
    )

    if let packed = pack(list, "zip"):
        bench_unpack(packed)

def bench_unpack(packed: Bytes) -> Unit:
    bench(
        "archive.zip_unpack",
        2000,
        lambda () -> Int:
            if let e = unpack(packed, "zip"):
                return e.length()

            return 0
    )

def bench_sse() -> Unit:
    let stream = sse_stream(2000)

    bench(
        "sse.feed",
        2000,
        lambda () -> Int:
            if let d = decoder():
                return feed_all(d, stream)

            return 0
    )

def feed_all(d: SseDecoder, stream: Bytes) -> Int:
    if let events = d.feed(stream):
        return events.length()

    return 0

export def bench_host() -> Unit:
    bench_archive()
    bench_sse()

    bench(
        "time.timestamp_to_string",
        20000,
        lambda () -> Int:
            var n = 0
            if let t = parse_timestamp("2026-03-01T12:30:45.123Z"):
                for i in 0..20000:
                    n += t.to_string().length()
            return n
    )

    bench(
        "random.uuid_v4",
        20000,
        lambda () -> Int:
            var n = 0
            let source = entropy()
            for i in 0..20000:
                if let u = uuid_v4(source):
                    n += u.length()
            return n
    )
