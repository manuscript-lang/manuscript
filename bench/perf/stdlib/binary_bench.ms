import keep, measure from "@std/test/bench.ms"
import words from "./src/harness.ms"
import base64_encode, base64_decode, hex_encode from "@std/data/encoding.ms"
import sha256 from "@std/crypto.ms"
import Bytes, BytesBuilder from "@std/bytes.ms"

fn build_packed() Bytes:
    var bb = BytesBuilder()
    for j in 0..25000:
        bb.append_int32_le(j.to_int32().get(0))
    return bb.build()

bench "encoding.base64_encode":
    let blob = words(20000).join(",").to_bytes()
    try measure(blob.length(), fn: keep(base64_encode(blob).length()))

bench "encoding.base64_decode":
    let blob = words(20000).join(",").to_bytes()
    let b64 = base64_encode(blob)

    fn work() Result[Unit, Error]:
        if let b = base64_decode(b64):
            return keep(b.length())

        return keep(0)

    try measure(blob.length(), work)

bench "encoding.hex_encode":
    let blob = words(20000).join(",").to_bytes()
    try measure(blob.length(), fn: keep(hex_encode(blob).length()))

bench "crypto.sha256":
    let blob = words(20000).join(",").to_bytes()
    try measure(blob.length(), fn: keep(sha256(blob).length()))

bench "bytes.builder":
    fn work() Result[Unit, Error]:
        var bb = BytesBuilder()
        for j in 0..100000:
            bb.append((j % 256).to_uint8().get(0))
        return keep(bb.build().length())

    try measure(100000, work)

bench "bytes.read_int32_le":
    let packed = build_packed()

    fn work() Result[Unit, Error]:
        var sum = 0
        for j in 0..25000:
            sum += packed.int32_le(j * 4).get(0).to_int()
        return keep(sum)

    try measure(25000, work)

bench "bytes.read_uint32_le":
    let packed = build_packed()

    fn work() Result[Unit, Error]:
        var sum = 0
        for j in 0..25000:
            sum += packed.uint32_le(j * 4).get(0).to_int()
        return keep(sum)

    try measure(25000, work)

bench "bytes.append_int32_le":
    fn work() Result[Unit, Error]:
        var bb = BytesBuilder()
        for j in 0..100000:
            bb.append_int32_le(j.to_int32().get(0))
        return keep(bb.build().length())

    try measure(100000, work)
