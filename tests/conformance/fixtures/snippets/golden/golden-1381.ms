// conform: tags=diagnostics
// conform: phase=check
import (
	panic from "@std/faults.ms",
	stderr, stdout from "@std/io/io.ms",
)

test "pass=a=b" {
	_out := stdout().write(data: "PASS fake\nstdout=a=b\n")
	_err := stderr().write(data: "stderr=a=b\n")
}

test "fails" {
	return panic(message: "distribution failure")
}

test "after" {
	return
}
