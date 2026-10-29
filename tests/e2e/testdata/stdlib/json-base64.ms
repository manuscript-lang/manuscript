import {parse, stringify, JsonError} from "@std/json.ms"
import {Bytes, BytesBuilder} from "@std/bytes.ms"
import expect_equal from "@std/test.ms"

test "typed JSON Base64 decodes every byte and preserves strict syntax":
    var bytes = BytesBuilder()
    for value in 0..256: bytes.append(value.to_uint8().get())

    let expected = [Bytes([]), Bytes([0]), Bytes([251, 255]), bytes.build()]
    let text = try stringify(expected)
    try expect_equal((try parse[List[Bytes]](text)), expected)
    try expect_equal((try parse[Bytes]("\"+/8=\"")), Bytes([251, 255]))

    let invalid: Result[Bytes, JsonError] = error(JsonError.InvalidData)
    for encoded in ["-_8=", "Zh==", "Zm9=", "=AAA", "AA=A", "éAA", "Zg== "]:
        try expect_equal(parse[Bytes]("\"{encoded}\""), invalid)
