// conform: tags=diagnostics
// conform: phase=check
import (
	File from "@std/io/io.ms",
	Connection from "@std/net/net.ms",
)

type Val {
	val Int
}
// expect-error: MS2002 4:5-4:9 module does not export File; @std/io/io.ms exports: DescriptorSink, DescriptorSource, Pipe, ReadStream, Sink, Source, StdStream, Transform, WriteStream, pipe, redirect_to_null, stderr, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/io/io.ms"'
