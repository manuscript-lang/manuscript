import bench from "./harness.ms"
import Bytes from "@std/bytes.ms"
import pack, unpack, ArchiveEntry from "@std/io/archive.ms"
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

fn bench_archive() Unit:
    list := entries(2000)

    bench(
        "archive.zip_pack",
        2000,
        fn() Int:
            if b := pack(list, "zip"):
                return b.length()

            return 0
    )

    bench(
        "archive.tar_pack",
        2000,
        fn() Int:
            if b := pack(list, "tar"):
                return b.length()

            return 0
    )

    if packed := pack(list, "zip"):
        bench_unpack(packed)

fn bench_unpack(packed: Bytes) Unit:
    bench(
        "archive.zip_unpack",
        2000,
        fn() Int:
            if e := unpack(packed, "zip"):
                return e.length()

            return 0
    )

fn bench_sse() Unit:
    stream := sse_stream(2000)

    bench(
        "sse.feed",
        2000,
        fn() Int:
            return count_events(stream.clone())
    )

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

export fn bench_host() Unit:
    bench_archive()
    bench_sse()

    bench(
        "time.timestamp_to_string",
        20000,
        fn() Int:
            var n = 0
            if t := parse_timestamp("2026-03-01T12:30:45.123Z"):
                for i in 0..20000:
                    n += t.to_string().length()
            return n
    )

    bench(
        "random.uuid_v4",
        20000,
        fn() Int:
            var n = 0
            for i in 0..20000:
                if u := uuid_v4():
                    n += u.length()
            return n
    )
