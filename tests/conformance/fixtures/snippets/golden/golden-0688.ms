// conform: tags=diagnostics
// conform: phase=check
import ReadStream, read_line from "@std/io/io.ms"

fn probe(input ReadStream) Bool {
	next := read_line
	if line := next(input) {
		return line.is_some()
	}

	return false
}
