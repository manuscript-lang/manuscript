# conform: tags=control-flow,diagnostics,modules,stdlib-fs,stdlib-process,tier-io,try-result
# conform: phase=check
# conform: origin=documentation/learn/common-tasks.md:94
import arguments from "@std/os/process.ms"
import write_file from "@std/os/fs.ms"

fn run() Result[Unit, Error]:
    let path = try arguments().first().ok_or(Error("filesystem: invalid input", kind: ErrorCategory.InvalidInput))
    return write_file(path, "saved notes\n", replace: false)

export fn main() Int:
    if run().is_error():
        return 1

    return 0
