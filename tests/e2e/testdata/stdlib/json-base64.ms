import (
    parse, stringify from "@std/data/json.ms",
    Bytes, BytesBuilder from "@std/bytes.ms",
    expect_equal, expect_error from "@std/test/test.ms",
)

test "typed JSON Base64 decodes every byte and preserves strict syntax":
    var bytes = BytesBuilder()
    for value in 0..256: bytes.append(value.to_uint8().get())

    let expected = [Bytes([]), Bytes([0]), Bytes([251, 255]), bytes.build()]
    let text = try stringify(expected)
    try expect_equal((try parse[List[Bytes]](text)), expected)
    try expect_equal((try parse[Bytes]("\"+/8=\"")), Bytes([251, 255]))
    for encoded in ["-_8=", "Zh==", "Zm9=", "=AAA", "AA=A", "éAA", "Zg== "]:
        try expect_equal(
            (try expect_error(parse[Bytes]("\"{encoded}\""))).kind, "EBADMSG"
        )
