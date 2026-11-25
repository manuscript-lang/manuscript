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
// expect-error: MS2002 7:5-7:17 module does not export CommandError; @std/os/process.ms exports: CommandOutput, Commands, CpuUsage, IdentityKind, NativeSignals, NativeSubprocess, ProcessInfo, ResourceUsage, RunOptions, Signal, SpawnOptions, Stdio, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/os/process.ms"'
// expect-error: MS2002 7:44-7:52 module does not export commands; did you mean 'Commands'?
