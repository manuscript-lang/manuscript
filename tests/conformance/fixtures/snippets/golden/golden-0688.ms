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
// expect-error: MS2002 3:20-3:29 module does not export read_line; @std/io/io.ms exports: DescriptorSink, DescriptorSource, Pipe, ReadStream, Sink, Source, StdStream, Transform, WriteStream, pipe, redirect_to_null, stderr, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/io/io.ms"'
// expect-error: MS3000 5:16 ReadStream requires 1 type arguments, found 0; write ReadStream[T1]
// expect-error: MS2001 6:13 unknown binding read_line; declare it with 'read_line := ...' before use, define 'fn read_line(...) T { ... }', or import it from a module
