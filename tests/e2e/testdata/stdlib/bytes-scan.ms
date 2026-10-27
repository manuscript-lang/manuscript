from "@std/test.ms" import expect_equal
from "@std/bytes.ms" import Bytes

test "index_of_byte finds a byte at or after start":
    let data = Bytes([1, 2, 3, 2, 255])
    try expect_equal(data.index_of_byte(2, 0), some(1))
    try expect_equal(data.index_of_byte(2, 2), some(3))
    try expect_equal(data.index_of_byte(255, 0), some(4))
    try expect_equal(data.index_of_byte(9, 0), none)

test "index_of_byte handles out-of-range arguments":
    let data = Bytes([1, 2])
    try expect_equal(data.index_of_byte(1, -3), some(0))
    try expect_equal(data.index_of_byte(1, 5), none)
    try expect_equal(data.index_of_byte(2, 2), none)
    try expect_equal(Bytes([]).index_of_byte(0, 0), none)

test "decode_utf8_range decodes a byte range":
    let data = "aé€b".to_bytes()
    try expect_equal(data.decode_utf8_range(0, data.length()), some("aé€b"))
    try expect_equal(data.decode_utf8_range(1, 3), some("é"))
    try expect_equal(data.decode_utf8_range(2, 3), none)
    try expect_equal(data.decode_utf8_range(2, 2), some(""))
