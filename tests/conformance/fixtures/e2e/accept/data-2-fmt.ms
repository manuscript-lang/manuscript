# conform: tags=formatter,modules,optional,parser,stdlib-bytes,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/data-2.ms
import expect_equal from "@std/test.ms"
import Bytes from "@std/bytes.ms"

test "explicit byte conversion":
    try expect_equal("é".byte_length(), 2)
    try expect_equal("é".to_bytes().decode_utf8(), some("é"))

    let invalid: String? = none
    try expect_equal(Bytes([255]).decode_utf8(), invalid)
    try expect_equal("-007".parse_int(), some(-7))
