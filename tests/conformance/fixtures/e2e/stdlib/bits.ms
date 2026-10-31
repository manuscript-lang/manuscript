# conform: tags=modules,stdlib-bits,stdlib-math,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/bits.ms
import expect_equal, expect_fault from "@std/test.ms"
import (
    bit_and,
    bit_or,
    bit_xor,
    bit_not,
    shift_left,
    shift_right,
    shift_right_unsigned,
    rotate_left,
    rotate_right,
    count_ones,
    leading_zeros,
    trailing_zeros,
    wrapping_add,
    wrapping_subtract,
    wrapping_multiply
) from "@std/math.ms"
import max_int, min_int from "@std/math.ms"

fn shift_too_far() Unit:
    let _value = shift_left(1, 64)
    return unit

fn shift_negative() Unit:
    let _value = shift_right(1, -1)
    return unit

test "bitwise operators follow two's complement":
    try expect_equal(bit_and(12, 10), 8)
    try expect_equal(bit_or(12, 10), 14)
    try expect_equal(bit_xor(12, 10), 6)
    try expect_equal(bit_not(0), -1)
    try expect_equal(bit_not(5), -6)

test "shifts distinguish arithmetic from logical":
    try expect_equal(shift_left(1, 10), 1024)
    try expect_equal(shift_right(-8, 1), -4)
    try expect_equal(shift_right_unsigned(-1, 63), 1)
    try expect_equal(shift_right_unsigned(8, 2), 2)

test "shift counts outside 0 through 63 fault":
    let _first = try expect_fault(shift_too_far)
    let _second = try expect_fault(shift_negative)

test "rotation and bit counts":
    try expect_equal(rotate_left(1, 64), 1)
    try expect_equal(rotate_left(1, 1), 2)
    try expect_equal(rotate_right(1, 1), min_int)
    try expect_equal(count_ones(255), 8)
    try expect_equal(count_ones(-1), 64)
    try expect_equal(leading_zeros(1), 63)
    try expect_equal(leading_zeros(0), 64)
    try expect_equal(trailing_zeros(8), 3)
    try expect_equal(trailing_zeros(0), 64)

test "wrapping arithmetic never faults":
    try expect_equal(wrapping_add(max_int, 1), min_int)
    try expect_equal(wrapping_subtract(min_int, 1), max_int)
    try expect_equal(wrapping_multiply(max_int, 2), -2)
