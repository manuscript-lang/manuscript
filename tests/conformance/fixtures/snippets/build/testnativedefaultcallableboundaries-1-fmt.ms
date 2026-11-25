// conform: tags=formatter,generics,modules,parser,stdlib-bytes,stdlib-csv,stdlib-encoding,stdlib-process,stdlib-time,tier-io
// conform: phase=parse
// conform: origin=pkg/build/native_defaults_test.go:11 TestNativeDefaultCallableBoundaries
import (
	Bytes from "@std/bytes.ms",
	CsvOptions, parse from "@std/data/csv.ms",
	base64_decode, base64_encode from "@std/data/encoding.ms",
	CommandOutput, Commands from "@std/os/process.ms",
	Duration from "@std/time.ms",
)

fn forward[T](item T) T => item
