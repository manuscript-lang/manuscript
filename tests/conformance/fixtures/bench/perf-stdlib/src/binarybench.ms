from "@std/collections.ms" import range
from "./harness.ms" import bench, words
from "@std/encoding.ms" import base64_encode, base64_decode, hex_encode
from "@std/crypto.ms" import sha256
from "@std/bytes.ms" import BytesBuilder

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
