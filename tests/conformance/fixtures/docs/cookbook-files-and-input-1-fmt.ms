// conform: tags=control-flow,formatter,modules,parser,stdlib-fs,stdlib-process,tier-io,try-result
// conform: phase=parse
// conform: origin=documentation/learn/common-tasks.md:94
import arguments from "@std/os/env.ms"
import write_file from "@std/os/fs.ms"

fn run() Result[Unit, Error]:
    path := try arguments().first().ok_or(
        Error("filesystem: invalid input", kind: "EINVAL")
    )
    return write_file(path, "saved notes\n", replace: false).wait()

fn main() Unit!:
    try run()
