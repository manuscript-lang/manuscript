import range from "@std/collections.ms"
import {bench, words} from "./harness.ms"
import {base64_encode, base64_decode, hex_encode} from "@std/encoding.ms"
import {sha256} from "@std/crypto.ms"
import {BytesBuilder} from "@std/bytes.ms"

export fn bench_binary() -> Unit:
    let blob = words(20000).join(separator: ",").to_bytes()
    bench(
        "encoding.base64_encode",
        blob.length(),
        fn() -> Int:
            return base64_encode(data: blob).length()
    )
    let b64 = base64_encode(data: blob)
    bench(
        "encoding.base64_decode",
        blob.length(),
        fn() -> Int:
            match base64_decode(text: b64):
            ok(b): return b.length()
            error(_): return 0
    )
    bench(
        "encoding.hex_encode",
        blob.length(),
        fn() -> Int:
            return hex_encode(data: blob).length()
    )
    bench(
        "crypto.sha256",
        blob.length(),
        fn() -> Int:
            return sha256(data: blob).length()
    )
    bench(
        "bytes.builder",
        100000,
        fn() -> Int:
            let bb = BytesBuilder()
            for j in range(0, 100000):
                bb.append(j % 256)
            return bb.freeze().length()
    )
