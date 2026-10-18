import {from_bytes, map, take, concat, tee, map_writer, digest} from "@std/streams.ms"
import {ReadStream, WriteStream, read_all, copy} from "@std/io.ms"
import {CompressionFormat} from "@std/compress.ms"
import {HashAlgorithm, sha256} from "@std/crypto.ms"
import Bytes from "@std/bytes.ms"
import panic from "@std/faults.ms"
import MemoryStream from "./support/streams.ms"

fn upper(chunk: Bytes) Bytes:
    return chunk.decode_utf8().get("").upper().to_bytes()

test "flows compose stream transforms":
    let output = MemoryStream("".to_bytes(), 0, closed: false)
    let source = from_bytes("hello world".to_bytes(), 4)
    let copied = source | map(upper) | take(8) | try copy(WriteStream(output))
    if copied != 8: return panic("byte count")
    if output.data != "HELLO WO".to_bytes(): return panic("pipeline output")

test "concat tee and writer helpers":
    let log = MemoryStream("".to_bytes(), 0, closed: false)
    let joined = concat([from_bytes("ab".to_bytes()), from_bytes("cd".to_bytes())])
    let seen = tee(joined, WriteStream(log))
    if (try read_all(seen)) != "abcd".to_bytes(): return panic("concat")
    if log.data != "abcd".to_bytes(): return panic("tee")

    let sink = MemoryStream("".to_bytes(), 0, closed: false)
    let writer = map_writer(WriteStream(sink), upper)
    try writer.write("quiet")
    try writer.write_bytes("!".to_bytes())
    if sink.data != "QUIET!".to_bytes(): return panic("map_writer")

test "digest hashes a stream incrementally":
    let data = "stream me, please".to_bytes()
    let hashed = try digest(from_bytes(data, 3), HashAlgorithm.Sha256)
    if hashed != sha256(data): return panic("stream digest")

test "compression streams round trip all formats":
    let text = "compress me compress me compress me".to_bytes()

    for format in [
        CompressionFormat.Gzip,
        CompressionFormat.Zlib,
        CompressionFormat.Deflate
    ]:
        let packed = format.compress_stream(from_bytes(text, 5))
        let restored = format.decompress_stream(packed)
        if (try read_all(restored)) != text: return panic(
            "compression stream roundtrip"
        )

    let limited = (
        CompressionFormat
        .Gzip
        .decompress_stream(
            CompressionFormat.Gzip.compress_stream(from_bytes(text)),
            some(4)
        )
    )
    if read_all(limited).is_ok(): return panic("decompression budget")

    let garbage = CompressionFormat.Gzip.decompress_stream(from_bytes(text))
    if read_all(garbage).is_ok(): return panic("invalid data")
