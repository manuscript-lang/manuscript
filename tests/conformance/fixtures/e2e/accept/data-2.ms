// conform: tags=modules,optional,stdlib-bytes,stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/data-2.ms
import (
	Bytes from "@std/bytes.ms",
	expect_equal from "@std/test/test.ms",
)

test "explicit byte conversion":
	expect_equal("é".byte_length(), 2)?
	expect_equal("é".to_bytes().decode_utf8(), "é")?

	invalid: String? := none
	expect_equal(Bytes([255]).decode_utf8(), invalid)?
	expect_equal("-007".parse_int(), -7)?
