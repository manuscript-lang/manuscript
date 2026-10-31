# conform: tags=control-flow,formatter,modules,parser,stdlib-fs,stdlib-process,tier-io,try-result
# conform: phase=parse
# conform: origin=documentation/learn/common-tasks.md:94
import arguments from "@std/process.ms"
import FileSystemError, write_file from "@std/fs.ms"

fn run() Result[Unit, Error]:
    let path = try arguments().first().ok_or(FileSystemError.InvalidInput)
    return write_file(path, "saved notes\n", replace: false)

export fn main() Int:
    if run().is_error():
        return 1

    return 0
