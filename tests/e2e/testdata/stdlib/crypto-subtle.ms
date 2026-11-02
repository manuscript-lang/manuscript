import Bytes from "@std/bytes.ms"
import (
    constant_time_less_or_equal,
    constant_time_select,
    xor_bytes
) from "@std/crypto.ms"
import expect_equal, expect_true from "@std/test/test.ms"

test "constant time select picks by choice":
    try expect_equal(constant_time_select(1, 7, 9), 7)
    try expect_equal(constant_time_select(0, 7, 9), 9)

test "constant time less-or-equal orders non-negative values":
    try expect_equal(constant_time_less_or_equal(3, 4), 1)
    try expect_equal(constant_time_less_or_equal(4, 4), 1)
    try expect_equal(constant_time_less_or_equal(5, 4), 0)
    try expect_equal(constant_time_less_or_equal(0, 0), 1)

test "xor_bytes combines equal lengths and rejects others":
    let mixed = xor_bytes(Bytes([1, 2, 255]), Bytes([3, 2, 15])).get(Bytes([]))
    try expect_equal(mixed.get(0).to_int(), 2)
    try expect_equal(mixed.get(1).to_int(), 0)
    try expect_equal(mixed.get(2).to_int(), 240)
    try expect_true(xor_bytes(Bytes([1]), Bytes([])).is_error())
