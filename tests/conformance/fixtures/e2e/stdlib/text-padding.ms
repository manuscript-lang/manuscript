// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_contains, expect_equal, expect_fault from "@std/test/test.ms"

test "padding returns a plain String":
	expect_equal("7".pad_start(3, "0"), "007")?
	expect_equal("id".pad_end(5, "."), "id...")?
	expect_equal("x".pad_start(4, "ab"), "abax")?
	expect_equal("x".pad_end(4, "ab"), "xaba")?

test "padding counts scalars":
	expect_equal("é".pad_start(3, "🙂"), "🙂🙂é")?
	expect_equal("x".pad_end(4, "é🙂"), "xé🙂é")?

test "repeated fills keep pattern and scalar boundaries":
	expect_equal("ab".repeat(17).get(), "ababababababababababababababababab")?
	expect_equal("é🙂".repeat(5).get(), "é🙂é🙂é🙂é🙂é🙂")?
	expect_equal("!".pad_start(10, "ab"), "ababababa!")?
	expect_equal("!".pad_end(6, "é🙂"), "!é🙂é🙂é")?

test "a short target, negative target or empty padding leaves the text unchanged":
	expect_equal("abc".pad_start(2, "-"), "abc")?
	expect_equal("abc".pad_end(3, "-"), "abc")?
	expect_equal("x".pad_start(-1, " "), "x")?
	expect_equal("x".pad_end(4, ""), "x")?
	expect_equal("".pad_start(2, ""), "")?

test "a table row needs no unwrap":
	row := "total".pad_end(8, " ") + 42.to_string().pad_start(5, " ")
	expect_equal(row, "total      42")?

test "padding beyond the string limit faults":
	message := expect_fault(
		fn:
			_huge := "ab".pad_start(9223372036854775807, "xyz")
	)?
	message | expect_contains("limit exceeded")?

test "fixed-digit float formatting returns a plain String":
	expect_equal(3.14159.to_fixed(2), "3.14")?
	expect_equal(2.5.to_fixed(0), "2")?
	expect_equal(1234.5.to_precision(3), "1.23e+3")?
	expect_equal(0.00015.to_exponential(1), "1.5e-4")?
	expect_equal(1.005.to_fixed(2), "1.00")?

test "a digit count outside the range faults":
	fixed := expect_fault(
		fn:
			_text := 1.0.to_fixed(101)
	)?
	fixed | expect_contains("to_fixed")?

	negative := expect_fault(
		fn:
			_text := 1.0.to_fixed(-1)
	)?
	negative | expect_contains("to_fixed")?

	precision := expect_fault(
		fn:
			_text := 1.0.to_precision(0)
	)?
	precision | expect_contains("to_precision")?

	exponential := expect_fault(
		fn:
			_text := 1.0.to_exponential(101)
	)?
	exponential | expect_contains("to_exponential")?
