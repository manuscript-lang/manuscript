import range from "@std/collections.ms"
import {bench} from "./harness.ms"
import Bytes from "@std/bytes.ms"
import {pack, unpack, ArchiveEntry} from "@std/archive.ms"
import {decoder, SseDecoder} from "@std/sse.ms"
import {parse_timestamp} from "@std/time.ms"
import {uuid_v4, entropy} from "@std/random.ms"

fn entries(count: Int) List[ArchiveEntry]:
    var out: List[ArchiveEntry] = []
    for i in range(0, count):
        out.append(
            ArchiveEntry(
                "dir/file{i}.txt",
                "contents of file {i}".to_bytes(),
                directory: false
            )
        )
    return out

fn sse_stream(count: Int) Bytes:
    var parts: List[String] = []
    for i in range(0, count):
        parts.append("event: tick\nid: {i}\ndata: payload {i}\ndata: second line\n\n")
    return parts.join("").to_bytes()

fn bench_archive() Unit:
    let list = entries(2000)
    bench(
        "archive.zip_pack",
        2000,
        fn() Int:
            if let b = pack(list, "zip"):
                return b.length()

            return 0
    )
    bench(
        "archive.tar_pack",
        2000,
        fn() Int:
            if let b = pack(list, "tar"):
                return b.length()

            return 0
    )
    if let packed = pack(list, "zip"):
        bench_unpack(packed)

fn bench_unpack(packed: Bytes) Unit:
    bench(
        "archive.zip_unpack",
        2000,
        fn() Int:
            if let e = unpack(packed, "zip"):
                return e.length()

            return 0
    )

fn bench_sse() Unit:
    let stream = sse_stream(2000)
    bench(
        "sse.feed",
        2000,
        fn() Int:
            if let d = decoder():
                return feed_all(d, stream)

            return 0
    )

fn feed_all(d: SseDecoder, stream: Bytes) Int:
    if let events = d.feed(stream):
        return events.length()

    return 0

export fn bench_host() Unit:
    bench_archive()
    bench_sse()
    bench(
        "time.timestamp_to_string",
        20000,
        fn() Int:
            var n = 0
            if let t = parse_timestamp("2026-03-01T12:30:45.123Z"):
                for i in range(0, 20000):
                    n += t.to_string().length()
            return n
    )
    bench(
        "random.uuid_v4",
        20000,
        fn() Int:
            var n = 0
            let source = entropy()
            for i in range(0, 20000):
                if let u = uuid_v4(source):
                    n += u.length()
            return n
    )
