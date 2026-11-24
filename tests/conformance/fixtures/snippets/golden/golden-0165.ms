// conform: tags=diagnostics
// conform: phase=check
import (
	Bytes from "@std/bytes.ms",
	CsvOptions, parse from "@std/data/csv.ms",
	base64_decode, base64_encode from "@std/data/encoding.ms",
	CommandError, CommandOutput, Commands, commands from "@std/os/process.ms",
	Duration from "@std/time.ms",
)

fn forward[T](item T) T => item
