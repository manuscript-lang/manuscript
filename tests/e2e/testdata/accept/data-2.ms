import {expect_equal} from "@std/testing.ms"
import Bytes from "@std/bytes.ms"

test "explicit byte conversion":
    "é".byte_length() | try expect_equal(expected: 2)
    "é".to_bytes().to_string() | try expect_equal(expected: some("é"))
    let invalid: Optional[String] = none
    Bytes([255]).to_string() | try expect_equal(expected: invalid)
    "-007".parse_int() | try expect_equal(expected: some(-7))
