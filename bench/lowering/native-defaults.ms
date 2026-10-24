from "@std/encoding.ms" import base64_encode
from "@std/csv.ms" import CsvOptions
from "@std/bytes.ms" import Bytes
from "@std/process.ms" import commands, CommandOutput, CommandError
from "@std/time.ms" import Duration
from "@std/fs.ms" import filesystem, FileSystem, FileSystemError

def direct_explicit(data: Bytes) -> String: base64_encode(data, False)

def direct_omitted(data: Bytes) -> String: base64_encode(data)

def bound_explicit(data: Bytes) -> String:
    let encode = base64_encode
    return encode(data, False)

def bound_omitted(data: Bytes) -> String:
    let encode = base64_encode
    return encode(data)

def encode_bind() -> Callable[[Bytes, Bool], String]: base64_encode

def csv_explicit() -> CsvOptions: CsvOptions(",", "\n")

def csv_omitted() -> CsvOptions: CsvOptions()

def command_explicit() -> Result[CommandOutput, CommandError]:
    return commands().run(program: "", arguments: [], input: "".to_bytes())

def command_omitted() -> Result[CommandOutput, CommandError]:
    return commands().run(program: "", arguments: [])

def command_bind() -> Callable[
    [String, List[String], Bytes, Optional[Int], Optional[Duration]],
    Result[CommandOutput, CommandError]
]:
    return commands().run

def filesystem_setup() -> FileSystem: filesystem()

def filesystem_explicit(fs: FileSystem, data: Bytes) -> Result[Unit, FileSystemError]:
    return fs.write_file_bytes("", data, False)

def filesystem_omitted(fs: FileSystem, data: Bytes) -> Result[Unit, FileSystemError]:
    return fs.write_file_bytes("", data)

def filesystem_bind(
    fs: FileSystem
) -> Callable[[String, Bytes, Bool], Result[Unit, FileSystemError]]:
    return fs.write_file
