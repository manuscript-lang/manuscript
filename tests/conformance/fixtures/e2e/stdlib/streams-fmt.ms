# conform: tags=control-flow,faults,formatter,modules,optional,parser,stdlib-bytes,stdlib-compress,stdlib-crypto,stdlib-faults,stdlib-io,stdlib-streams,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/streams.ms
import {from_bytes, map, take, concat, tee, map_writer, digest} from "@std/streams.ms"
import {read_all, copy} from "@std/io.ms"
import {CompressionFormat} from "@std/archive.ms"
import {HashAlgorithm, sha256} from "@std/crypto.ms"
import Bytes from "@std/bytes.ms"
import panic from "@std/core.ms"
import {filesystem} from "@std/fs.ms"
import expect_ok from "@std/testing.ms"

fn upper(chunk: Bytes) Bytes:
    return chunk.decode_utf8().get("").upper().to_bytes()

test "flows compose stream transforms":
    let fs = filesystem()

    with temporary = (fs.temporary("manuscript-streams-") | try expect_ok):
        let path = "{temporary.path()}/pipeline.bin"
        let output = (fs.open(path: path, flags: "w", mode: 420) | try expect_ok)
        let source = from_bytes("hello world".to_bytes(), 4)
        let copied = source | map(upper) | take(8) | try copy(output.writer())
        output.close()
        if copied != 8: return panic("byte count")
        if (fs.read_file(path: path) | try expect_ok) != "HELLO WO".to_bytes(): return panic(
            "pipeline output"
        )

test "concat tee and writer helpers":
    let fs = filesystem()

    with temporary = (fs.temporary("manuscript-streams-") | try expect_ok):
        let log_path = "{temporary.path()}/tee.bin"
        let log = (fs.open(path: log_path, flags: "w", mode: 420) | try expect_ok)
        let joined = concat([from_bytes("ab".to_bytes()), from_bytes("cd".to_bytes())])
        let seen = tee(joined, log.writer())
        if (try read_all(seen)) != "abcd".to_bytes(): return panic("concat")

        log.close()
        if (fs.read_file(path: log_path) | try expect_ok) != "abcd".to_bytes(): return panic(
            "tee"
        )

        let sink_path = "{temporary.path()}/writer.bin"
        let sink = (fs.open(path: sink_path, flags: "w", mode: 420) | try expect_ok)
        let writer = map_writer(sink.writer(), upper)
        try writer.write("quiet")
        try writer.write_bytes("!".to_bytes())
        sink.close()
        if (fs.read_file(path: sink_path) | try expect_ok) != "QUIET!".to_bytes(): return panic(
            "map_writer"
        )

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
