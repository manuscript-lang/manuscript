import expect_equal from "@std/test/test.ms"
import is_digit, is_mark, is_punctuation, is_symbol from "@std/unicode.ms"

test "general category predicates":
    is_digit(53) | try expect_equal(true)
    is_digit(1635) | try expect_equal(false)
    is_punctuation(33) | try expect_equal(true)
    is_punctuation(8230) | try expect_equal(true)
    is_punctuation(97) | try expect_equal(false)
    is_symbol(36) | try expect_equal(true)
    is_symbol(97) | try expect_equal(false)
    is_mark(769) | try expect_equal(true)
    is_mark(97) | try expect_equal(false)
    is_punctuation(-1) | try expect_equal(false)
    is_symbol(55296) | try expect_equal(false)
