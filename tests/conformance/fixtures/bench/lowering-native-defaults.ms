// conform: tags=closures,diagnostics,lists,modules,optional,stdlib-bytes,stdlib-csv,stdlib-encoding,stdlib-fs,stdlib-process,stdlib-time,strings,tier-io,try-result
// conform: phase=check
// conform: origin=bench/lowering/native-defaults.ms
import base64_encode from "@std/data/encoding.ms"
import CsvOptions from "@std/data/csv.ms"
import Bytes from "@std/bytes.ms"
import CommandOutput, RunOptions, run from "@std/os/process.ms"
import Duration from "@std/time.ms"
import write_file_bytes from "@std/os/fs.ms"

fn direct_explicit(data: Bytes) String: base64_encode(data, false)

fn direct_omitted(data: Bytes) String: base64_encode(data)

fn bound_explicit(data: Bytes) String:
    let encode = base64_encode
    return encode(data, false)

fn bound_omitted(data: Bytes) String:
    let encode = base64_encode
    return encode(data)

fn encode_bind() fn(Bytes, Bool) String: base64_encode

fn csv_explicit() CsvOptions: CsvOptions(",", "\n")

fn csv_omitted() CsvOptions: CsvOptions()

fn command_explicit() CommandOutput!:
    return run("", [], RunOptions(input: "".to_bytes())).wait()

fn command_omitted() CommandOutput!:
    return run("", []).wait()

fn command_bind() fn(String, List[String], RunOptions) CommandOutput!:
    return run

fn filesystem_explicit(data: Bytes) Unit!:
    return write_file_bytes("", data, false).wait()

fn filesystem_omitted(data: Bytes) Unit!:
    return write_file_bytes("", data).wait()

fn filesystem_bind() fn(String, Bytes, Bool) Unit!:
    return fs.write_file
