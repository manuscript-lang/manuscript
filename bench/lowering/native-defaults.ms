import Promise from "@std/concurrency/promise.ms"
import base64_encode from "@std/data/encoding.ms"
import CsvOptions from "@std/data/csv.ms"
import Bytes from "@std/bytes.ms"
import CommandOutput, RunOptions, run from "@std/os/process.ms"
import Duration from "@std/time.ms"
import Writable from "@std/core.ms"
import write_file from "@std/os/fs.ms"

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

fn command_explicit() Result[CommandOutput, Error]:
    return run("", [], RunOptions(input: "".to_bytes())).wait()

fn command_omitted() Result[CommandOutput, Error]:
    return run("", []).wait()

fn command_bind() fn(String, List[String], RunOptions) Promise[CommandOutput]:
    return run

fn filesystem_explicit(data: Bytes) Result[Unit, Error]:
    return write_file("", data, false).wait()

fn filesystem_omitted(data: Bytes) Result[Unit, Error]:
    return write_file("", data).wait()

fn filesystem_bind() fn(String, Writable, Bool) Promise[Unit]:
    return write_file
