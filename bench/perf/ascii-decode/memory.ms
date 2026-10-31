import ascii_decode from "@std/encoding.ms"
import expect_equal from "@std/test.ms"

fn work() Unit!:
    let expected = try "A".repeat(1048576)
    let data = expected.to_bytes()
    var checksum = 0
    for unused in 0..32:
        checksum += (try ascii_decode(data)).byte_length()
    try expect_equal(checksum, 33554432)
    return ok(unit)

export fn main() Int:
    work().get()
    return 0
