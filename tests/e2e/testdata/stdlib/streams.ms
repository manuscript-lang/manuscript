import from_bytes, map, take, concat, tee, map_writer, digest from "@std/streams.ms"
import read_all, copy, IoError, read_line from "@std/io.ms"
import CompressionFormat from "@std/archive.ms"
import HashAlgorithm, sha256 from "@std/crypto.ms"
import Bytes from "@std/bytes.ms"
import panic from "@std/core.ms"
import open, read_file, temporary from "@std/fs.ms"
import expect_ok from "@std/test.ms"

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
