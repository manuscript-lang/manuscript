# conform: tags=control-flow,formatter,modules,parser,stdlib-fs,stdlib-io,stdlib-process,tier-io,try-result
# conform: phase=parse
# conform: origin=documentation/learn/common-tasks.md:63
import arguments from "@std/os/process.ms"
import FileSystemError, read_file from "@std/os/fs.ms"
import stdout from "@std/io/io.ms"

fn run() Result[Unit, Error]:
    let path = try arguments().first().ok_or(FileSystemError.InvalidInput)
    let text = try read_file(path, max_bytes: 1048576) | .decode_utf8().ok_or(
        FileSystemError.InvalidData
    ) | try
    try stdout().write(text)
    return stdout().flush()

export fn main() Int:
    if run().is_error():
        return 1

    return 0
