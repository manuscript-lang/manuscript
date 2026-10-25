from "@std/collections.ms" import range
from "./harness.ms" import bench, words
from "@std/encoding.ms" import base64_encode, base64_decode, hex_encode
from "@std/crypto.ms" import sha256
from "@std/bytes.ms" import Bytes, BytesBuilder

export def bench_binary() -> Unit:
    let blob = words(20000).join(",").to_bytes()
    bench(
        "encoding.base64_encode", blob.length(),
        lambda () -> Int: return base64_encode(blob).length()
    )

    let b64 = base64_encode(blob)

    bench(
        "encoding.base64_decode",
        blob.length(),
        lambda () -> Int:
            if let b = base64_decode(b64):
                return b.length()

            return 0
    )

    bench(
        "encoding.hex_encode", blob.length(),
        lambda () -> Int: return hex_encode(blob).length()
    )
    bench(
        "crypto.sha256", blob.length(), lambda () -> Int: return sha256(blob).length()
    )

    bench(
        "bytes.builder",
        100000,
        lambda () -> Int:
            var bb = BytesBuilder()
            for j in range(0, 100000):
                bb.append(j % 256)
            return bb.build().length()
    )

    let packed = build_packed()

    bench(
        "bytes.read_int32_le",
        25000,
        lambda () -> Int:
            var sum = 0
            for j in range(0, 25000):
                sum += packed.int32_le(j * 4).get(0).to_int()
            return sum
    )

    bench(
        "bytes.read_uint32_le",
        25000,
        lambda () -> Int:
            var sum = 0
            for j in range(0, 25000):
                sum += packed.uint32_le(j * 4).get(0)
            return sum
    )

    bench(
        "bytes.append_int32_le",
        100000,
        lambda () -> Int:
            var bb = BytesBuilder()
            for j in range(0, 100000):
                bb.append_int32_le(j.to_int32().get(0))
            return bb.build().length()
    )

def build_packed() -> Bytes:
    var bb = BytesBuilder()
    for j in range(0, 25000):
        bb.append_int32_le(j.to_int32().get(0))
    return bb.build()
