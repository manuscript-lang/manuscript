import (
    from_bytes,
    map,
    take,
    concat,
    tee,
    map_writer,
    digest,
    multi_writer,
    section,
    channel_reader,
    channel_writer
) from "@std/io/streams.ms"
import read_all, copy, IoError, read_line from "@std/io/io.ms"
import CompressionFormat from "@std/io/archive.ms"
import HashAlgorithm, sha256 from "@std/crypto.ms"
import Bytes from "@std/bytes.ms"
import panic from "@std/core.ms"
import open, read_file, temporary, write_file from "@std/os/fs.ms"
import Channel from "@std/io/channels.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import expect_ok from "@std/test/test.ms"

fn upper(chunk: Bytes) Bytes:
    return chunk.decode_utf8().get("").upper().to_bytes()

test "flows compose stream transforms":
    let temporary = temporary("manuscript-streams-") | try expect_ok
    let path = "{temporary.path()}/pipeline.bin"
    var output = open(path: path, flags: "w", mode: 420) | try expect_ok
    let source = from_bytes("hello world".to_bytes(), 4)
    let copied = source | map(upper) | take(8) | try copy(output.writer())
    try output.close()
    if copied != 8: return panic("byte count")
    if (read_file(path: path) | try expect_ok) != "HELLO WO".to_bytes(): return panic(
        "pipeline output"
    )

test "concat tee and writer helpers":
    let temporary = temporary("manuscript-streams-") | try expect_ok
    let log_path = "{temporary.path()}/tee.bin"
    var log = open(path: log_path, flags: "w", mode: 420) | try expect_ok
    let joined = concat([from_bytes("ab".to_bytes()), from_bytes("cd".to_bytes())])
    let seen = tee(joined, log.writer())
    if (try read_all(seen)) != "abcd".to_bytes(): return panic("concat")

    try log.close()
    if (read_file(path: log_path) | try expect_ok) != "abcd".to_bytes(): return panic(
        "tee"
    )

    let sink_path = "{temporary.path()}/writer.bin"
    var sink = open(path: sink_path, flags: "w", mode: 420) | try expect_ok
    var writer = map_writer(sink.writer(), upper)
    try writer.write("quiet")
    try writer.write_bytes("!".to_bytes())
    try sink.close()
    if (read_file(path: sink_path) | try expect_ok) != "QUIET!".to_bytes(): return panic(
        "map_writer"
    )

test "digest hashes a stream incrementally":
    let data = "stream me, please".to_bytes()
    var input = from_bytes(data.clone(), 3)
    let hashed = try digest(var input, HashAlgorithm.Sha256)
    if hashed != sha256(data): return panic("stream digest")

test "compression streams round trip all formats":
    let text = "compress me compress me compress me".to_bytes()

    for format in [
        CompressionFormat.Gzip, CompressionFormat.Zlib, CompressionFormat.Deflate
    ]:
        let packed = format.compress_stream(from_bytes(text.clone(), 5))
        let restored = format.decompress_stream(packed)
        if (try read_all(restored)) != text: return panic(
            "compression stream roundtrip"
        )

    let limited = CompressionFormat.Gzip.decompress_stream(
        CompressionFormat.Gzip.compress_stream(from_bytes(text.clone())), 4
    )
    if read_all(limited).is_ok(): return panic("decompression budget")

    let garbage = CompressionFormat.Gzip.decompress_stream(from_bytes(text.clone()))
    if read_all(garbage).is_ok(): return panic("invalid data")

test "take rejects a negative limit and read_line counts the terminator":
    var negative = take(from_bytes("abc".to_bytes()), -1)
    let failed = negative.read()
    if failed.is_ok() or failed.err() != IoError.InvalidInput: return panic(
        "negative take"
    )

    var zero = take(from_bytes("abc".to_bytes()), 0)
    if (zero.read() | try expect_ok).is_some(): return panic("zero take")

    var terminated = from_bytes("abc\nx".to_bytes())
    if read_line(terminated, 3).is_ok(): return panic("terminated line at the limit")

    var roomy = from_bytes("abc\nx".to_bytes())
    if (read_line(roomy, 4) | try expect_ok) != "abc": return panic(
        "line under the limit"
    )

    var unterminated = from_bytes("abc".to_bytes())
    if (read_line(unterminated, 3) | try expect_ok) != "abc": return panic(
        "final line at the limit"
    )

fn produce(ch: Channel[Bytes, Unit]) Unit:
    var sink = channel_writer(ch)
    sink.write("alpha ").get()
    sink.write_bytes("beta ".to_bytes()).get()
    sink.write("gamma").get()
    sink.close()

test "channel pipe carries a task's writes to a reader":
    var group = TaskGroup[Unit, Unit, Bytes]()
    let task = group.spawn(produce)
    var source = channel_reader(task.channel.clone())
    let first = (try source.read(3)).get()
    if first != "alp".to_bytes(): return panic("partial chunk")

    let rest = try read_all(source)
    if rest != "ha beta gamma".to_bytes(): return panic("rest")

    try group.close()

test "multi_writer duplicates writes":
    let temporary = temporary("manuscript-streams-") | try expect_ok
    let first = "{temporary.path()}/first.bin"
    let second = "{temporary.path()}/second.bin"
    var one = open(path: first, flags: "w", mode: 420) | try expect_ok
    var two = open(path: second, flags: "w", mode: 420) | try expect_ok
    var both = multi_writer([one.writer(), two.writer()])
    try both.write("left")
    try both.write_bytes(" right".to_bytes())
    try both.flush()
    try one.close()
    try two.close()
    if (read_file(path: first) | try expect_ok) != "left right".to_bytes(): return panic(
        "first"
    )
    if (read_file(path: second) | try expect_ok) != "left right".to_bytes(): return panic(
        "second"
    )

test "sections read independent ranges of one file":
    let temporary = temporary("manuscript-streams-") | try expect_ok
    let path = "{temporary.path()}/data.bin"
    write_file(path: path, data: "0123456789abcdef") | try expect_ok

    var file = open(path: path, flags: "r", mode: 0) | try expect_ok
    let middle = section(file, 4, 6) | try expect_ok
    let tail = section(file, 12, 100) | try expect_ok
    if (try read_all(middle)) != "456789".to_bytes(): return panic("middle")
    if (try read_all(tail)) != "cdef".to_bytes(): return panic("tail")

    let bad = section(file, -1, 3)
    if not bad.is_error(): return panic("negative offset")
    if (file.read(2) | try expect_ok).get() != "01".to_bytes(): return panic(
        "position moved"
    )
