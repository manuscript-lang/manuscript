// conform: tags=diagnostics
// conform: phase=check
import (
	stderr, stdout from "@std/io/io.ms",
	fail from "@std/test/test.ms",
)

test "first=pass" {
	_out := stdout().write(data: "PASS fake test\nuser stdout\n")
	_err := stderr().write(data: "user stderr\n")
}

test "second=fails" {
	return fail("expected failure")
}

test "third=after" {
	return
}
// expect-error: MS3004 9:28 unknown argument data; parameters of write: value
// expect-error: MS3003 9:22 missing argument value: String in call to write; add 'value: <String>'
// expect-error: MS3004 10:28 unknown argument data; parameters of write: value
// expect-error: MS3003 10:22 missing argument value: String in call to write; add 'value: <String>'
