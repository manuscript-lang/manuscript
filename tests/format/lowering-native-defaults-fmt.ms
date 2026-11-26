// conform: tags=closures,formatter,lists,modules,optional,parser,stdlib-bytes,stdlib-csv,stdlib-encoding,stdlib-fs,stdlib-process,stdlib-time,strings,tier-io,try-result
// conform: phase=parse
// conform: origin=bench/perf/lowering/native-defaults.ms
import (
	Bytes from "@std/bytes.ms",
	CsvOptions from "@std/data/csv.ms",
	base64_encode from "@std/data/encoding.ms",
	write_file_bytes from "@std/os/fs.ms",
	CommandOutput, RunOptions, run from "@std/os/process.ms",
	Duration from "@std/time.ms",
)

fn direct_explicit(data Bytes) String => base64_encode(data, false)

fn direct_omitted(data Bytes) String => base64_encode(data)

fn bound_explicit(data Bytes) String {
	encode := base64_encode
	return encode(data, false)
}

fn bound_omitted(data Bytes) String {
	encode := base64_encode
	return encode(data)
}

fn encode_bind() fn(Bytes, Bool, Bool) String => base64_encode

fn csv_explicit() CsvOptions => CsvOptions(",", "\n")

fn csv_omitted() CsvOptions => CsvOptions()

fn command_explicit() CommandOutput! {
	return run("", [], RunOptions(input: "".to_bytes())).wait()
}

fn command_omitted() CommandOutput! {
	return run("", []).wait()
}

fn command_bind() fn(String, List[String], Bytes, Int?, Duration?) CommandOutput! {
	return run
}

fn filesystem_explicit(data Bytes) Void! {
	return write_file_bytes("", data, false).wait()
}

fn filesystem_omitted(data Bytes) Void! {
	return write_file_bytes("", data).wait()
}

fn filesystem_bind() fn(String, Bytes, Bool) Void! {
	return fs.write_file
}
// expect-format: unchanged
