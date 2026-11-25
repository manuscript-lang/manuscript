// conform: tags=diagnostics
// conform: phase=check
import stdout from "@std/io/io.ms"

fn never() Int {
	return 1
}

fn main() Void {
	_written := stdout().write(data: "TARGET_RAN\n")
}
