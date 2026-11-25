// conform: tags=diagnostics
// conform: phase=check
import File, IoError, files from "@std/io/io.ms"

type Holder {
	file File
	label String
}

export fn main() Int {
	opened := files().open("data.txt")
	if opened.is_error() {
		return 4
	}

	file := opened.get()
	read := file.read(1)
	if read.is_error() {
		return 7
	}

	chunk := read.get()

	match chunk {
		data => {
			if data.decode_utf8() != "d" {
				return 5
			}
		}
		null => {
			return 6
		}
	}

	original := Holder(file: file, label: "original")
	copy := original.clone()
	copy.label = "copy"
	if original.label != "original" {
		return 1
	}

	copy.file.close()

	reread := original.file.read(1)
	if reread.is_ok() {
		return 3
	}

	cause := reread.err()

	match cause {
		IoError.Closed => {
			return 0
		}
		_ => {
			return 2
		}
	}
}
// expect-error: MS2002 3:8-3:12 module does not export File; @std/io/io.ms exports: DescriptorSink, DescriptorSource, Pipe, ReadStream, Sink, Source, StdStream, Transform, WriteStream, pipe, redirect_to_null, stderr, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/io/io.ms"'
// expect-error: MS2002 3:14-3:21 module does not export IoError; @std/io/io.ms exports: DescriptorSink, DescriptorSource, Pipe, ReadStream, Sink, Source, StdStream, Transform, WriteStream, pipe, redirect_to_null, stderr, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/io/io.ms"'
// expect-error: MS2002 3:23-3:28 module does not export files; @std/io/io.ms exports: DescriptorSink, DescriptorSource, Pipe, ReadStream, Sink, Source, StdStream, Transform, WriteStream, pipe, redirect_to_null, stderr, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/io/io.ms"'
// expect-error: MS2001 6:10 unknown type File; declare it with 'type File:' / 'enum File:' / 'interface File:', declare it as a type parameter, or import it
// expect-error: MS2001 11:15 unknown binding files; host handle getters were removed: import the operation itself, e.g. read_file from "@std/os/fs.ms", connect from "@std/net/net.ms", run from "@std/os/process.ms", now from "@std/time.ms"
