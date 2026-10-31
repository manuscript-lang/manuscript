import base64_encode from "@std/encoding.ms"
import CsvOptions from "@std/csv.ms"
import Bytes from "@std/bytes.ms"
import commands, CommandOutput, CommandError from "@std/process.ms"
import Duration from "@std/time.ms"
import write_file_bytes, FileSystemError from "@std/fs.ms"

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

fn command_explicit() Result[CommandOutput, CommandError]:
    return commands().run(program: "", arguments: [], input: "".to_bytes())

fn command_omitted() Result[CommandOutput, CommandError]:
    return commands().run(program: "", arguments: [])

fn command_bind() fn(
    String,
    List[String],
    Bytes,
    Int?,
    Duration?
) Result[CommandOutput, CommandError]:
    return commands().run

fn filesystem_explicit(data: Bytes) Result[Unit, FileSystemError]:
    return write_file_bytes("", data, false)

fn filesystem_omitted(data: Bytes) Result[Unit, FileSystemError]:
    return write_file_bytes("", data)

fn filesystem_bind() fn(String, Bytes, Bool) Result[Unit, FileSystemError]:
    return write_file_bytes
