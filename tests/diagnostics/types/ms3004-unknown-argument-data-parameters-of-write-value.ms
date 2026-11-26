// conform: tags=diagnostics
// conform: phase=check
import (
	stdout from "@std/io/io.ms",
	nanoseconds, sleep from "@std/time.ms",
)

fn main() Void {
	stdout().write(data: "ready\n")
	sleep(nanoseconds(60000000000))
}
// expect-error: MS3004 9:20 unknown argument data; parameters of write: value
// expect-error: MS3003 9:14 missing argument value: String in call to write; add 'value: <String>'
// expect-error: MS3000 9:5 this statement discards Void!, so a failure would be lost; write a trailing '?' to propagate it, 'if value := x' or 'match' to handle it, or 'void ...' to drop it on purpose
