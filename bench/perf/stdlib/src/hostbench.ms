import range from "@std/collections.ms"
import {bench} from "./harness.ms"
import Bytes from "@std/bytes.ms"
import {pack, unpack, ArchiveEntry} from "@std/archive.ms"
import {decoder, feed, SseDecoder} from "@std/sse.ms"
import {parse_timestamp} from "@std/time.ms"
import {uuid_v4, entropy} from "@std/random.ms"

fn entries(count: Int) -> List[ArchiveEntry]:
    let out: List[ArchiveEntry] = []
    for i in range(0, count):
        out.append(
            ArchiveEntry(
                path: "dir/file{i}.txt",
                data: "contents of file {i}".to_bytes(),
                directory: false
            )
        )
    return out

fn sse_stream(count: Int) -> Bytes:
    let parts: List[String] = []
    for i in range(0, count):
        parts.append("event: tick\nid: {i}\ndata: payload {i}\ndata: second line\n\n")
    return parts.join(separator: "").to_bytes()

fn bench_archive() -> Unit:
    let list = entries(2000)
    bench(
        "archive.zip_pack",
        2000,
        fn() -> Int:
            match pack(entries: list, format: "zip"):
                ok(b): return b.length()
                error(_): return 0
    )
    bench(
        "archive.tar_pack",
        2000,
        fn() -> Int:
            match pack(entries: list, format: "tar"):
                ok(b): return b.length()
                error(_): return 0
    )

    match pack(entries: list, format: "zip"):
        ok(packed): bench_unpack(packed)
        error(_): unit

fn bench_unpack(packed: Bytes) -> Unit:
    bench(
        "archive.zip_unpack",
        2000,
        fn() -> Int:
            match unpack(data: packed, format: "zip"):
                ok(e): return e.length()
                error(_): return 0
    )

fn bench_sse() -> Unit:
    let stream = sse_stream(2000)
    bench(
        "sse.feed",
        2000,
        fn() -> Int:
            match decoder():
                ok(d): return feed_all(d, stream)
                error(_): return 0
    )

fn feed_all(d: SseDecoder, stream: Bytes) -> Int:
    match feed(decoder: d, chunk: stream):
        ok(events): return events.length()
        error(_): return 0

export fn bench_host() -> Unit:
    bench_archive()
    bench_sse()
    bench(
        "time.timestamp_to_string",
        20000,
        fn() -> Int:
            var n = 0

            match parse_timestamp(text: "2026-03-01T12:30:45.123Z"):
                ok(t):
                    for i in range(0, 20000):
                        n = n + t.to_string().length()
                error(_): unit

            return n
    )
    bench(
        "random.uuid_v4",
        20000,
        fn() -> Int:
            var n = 0
            let source = entropy()

            for i in range(0, 20000):
                match uuid_v4(entropy: source):
                    ok(u): n = n + u.length()
                    error(_): unit

            return n
    )
