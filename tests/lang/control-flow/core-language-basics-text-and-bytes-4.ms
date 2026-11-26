// conform: tags=control-flow,faults,formatter,modules,optional,stdlib-bytes,stdlib-faults,strings,testing,tier-stdlib
// conform: phase=test,parse
// conform: origin=documentation/core-language/basics/text-and-bytes.md:110
import (
	Bytes from "@std/bytes.ms",
	panic from "@std/core.ms",
)

test "explicit byte conversion" {
	if not ("é".length() == 2) {
		return panic("check failed")
	}
	if not ("é".to_bytes().decode_utf8() == "é") {
		return panic("check failed")
	}

	invalid String? := null
	if not (Bytes([255]).decode_utf8() == invalid) {
		return panic("check failed")
	}
	if not ("-007".parse_int() == -7) {
		return panic("check failed")
	}
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
