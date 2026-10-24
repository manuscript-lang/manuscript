from "@std/testing.ms" import expect_equal
from "@std/bytes.ms" import Bytes

test "explicit byte conversion":
    try expect_equal("é".byte_length(), 2)
    try expect_equal("é".to_bytes().decode_utf8(), some("é"))

    let invalid: Optional[String] = none
    try expect_equal(Bytes([255]).decode_utf8(), invalid)
    try expect_equal("-007".parse_int(), some(-7))
