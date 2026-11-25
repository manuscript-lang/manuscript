// conform: tags=diagnostics
// conform: phase=check
import ReadStream, read_line, stdin from "@std/io/io.ms"

fn limit() Int {
	return 1 / 0
}

fn probe(input ReadStream) Bool {
	if line := read_line(input, limit()) {
		return line.is_some()
	}
	return false
}

export fn main() Int {
	if probe(stdin()) { return 1 }
	return 0
}
// expect-error: MS2002 3:20-3:29 module does not export read_line; @std/io/io.ms exports: DescriptorSink, DescriptorSource, Pipe, ReadStream, Sink, Source, StdStream, Transform, WriteStream, pipe, redirect_to_null, stderr, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/io/io.ms"'
// expect-error: MS3000 9:16 ReadStream requires 1 type arguments, found 0; write ReadStream[T1]
// expect-error: MS3000 6:14 division by zero always faults; guard the divisor or use a nonzero constant
// expect-error: MS2001 10:16 unknown binding read_line; declare it with 'read_line := ...' before use, define 'fn read_line(...) T { ... }', or import it from a module
// expect-error: MS3001 17:14 expected ReadStream, found ReadStream[Bytes] (in argument 'input' of probe)
