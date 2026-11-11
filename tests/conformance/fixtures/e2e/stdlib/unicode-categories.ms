// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	expect_equal from "@std/test/test.ms",
	is_digit, is_mark, is_punctuation, is_symbol from "@std/unicode.ms",
)

test "general category predicates":
	is_digit(53) | expect_equal(true)?
	is_digit(1635) | expect_equal(false)?
	is_punctuation(33) | expect_equal(true)?
	is_punctuation(8230) | expect_equal(true)?
	is_punctuation(97) | expect_equal(false)?
	is_symbol(36) | expect_equal(true)?
	is_symbol(97) | expect_equal(false)?
	is_mark(769) | expect_equal(true)?
	is_mark(97) | expect_equal(false)?
	is_punctuation(-1) | expect_equal(false)?
	is_symbol(55296) | expect_equal(false)?
