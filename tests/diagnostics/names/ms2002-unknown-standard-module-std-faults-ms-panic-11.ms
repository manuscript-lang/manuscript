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
// expect-error: MS2002 4:5-4:10 unknown standard module @std/faults.ms; panic is exported by another standard module, so write: import panic from "@std/core.ms"
// expect-error: MS3004 9:28 unknown argument data; parameters of write: value
// expect-error: MS3003 9:22 missing argument value: String in call to write; add 'value: <String>'
// expect-error: MS3004 10:28 unknown argument data; parameters of write: value
// expect-error: MS3003 10:22 missing argument value: String in call to write; add 'value: <String>'
// expect-error: MS2001 14:12 unknown binding panic; add: import panic from "@std/core.ms"
// expect-fix: 1:1-1:1 "import panic from \"@std/core.ms\"\n"
