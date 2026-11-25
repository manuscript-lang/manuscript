// conform: tags=diagnostics
// conform: phase=check
import stdout from "@std/io/io.ms"

fn never() Int {
	return 1
}

fn main() Void {
	_written := stdout().write(data: "TARGET_RAN\n")
}
// expect-error: MS3004 10:32 unknown argument data; parameters of write: value
// expect-error: MS3003 10:26 missing argument value: String in call to write; add 'value: <String>'
