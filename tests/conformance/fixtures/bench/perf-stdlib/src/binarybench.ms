import {bench, words} from "./harness.ms"
import {base64_encode, base64_decode, hex_encode} from "@std/encoding.ms"
import sha256 from "@std/crypto.ms"
import BytesBuilder from "@std/bytes.ms"

export fn bench_binary() Unit:
    let blob = words(20000).join(",").to_bytes()
    bench(
        "encoding.base64_encode", blob.length(),
        fn() Int: return base64_encode(blob).length()
    )

    let b64 = base64_encode(blob)

    bench(
        "encoding.base64_decode",
        blob.length(),
        fn() Int:
            if let b = base64_decode(b64):
                return b.length()

            return 0
    )

    bench(
        "encoding.hex_encode", blob.length(), fn() Int: return hex_encode(blob).length()
    )
    bench("crypto.sha256", blob.length(), fn() Int: return sha256(blob).length())

    bench(
        "bytes.builder",
        100000,
        fn() Int:
            var bb = BytesBuilder()
            for j in 0..100000:
                bb.append(j % 256)
            return bb.build().length()
    )
