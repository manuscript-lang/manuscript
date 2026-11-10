// conform: tags=control-flow,diagnostics,modules,stdlib-fs,stdlib-io,stdlib-process,tier-io,try-result
// conform: phase=check
// conform: origin=documentation/learn/common-tasks.md:63
import arguments from "@std/os/env.ms"
import read_file from "@std/os/fs.ms"
import stdout from "@std/io/io.ms"

fn run() Result[Unit, Error]:
    let path = try arguments().first().ok_or(
        Error("filesystem: invalid input", kind: "EINVAL")
    )
    let text = try read_file(path, max_bytes: 1048576).wait() | .decode_utf8().ok_or(
        Error("filesystem: invalid data", kind: "EBADMSG")
    ) | try
    try stdout().write(text)
    return stdout().flush()

fn main() Unit!:
    try run()
    return ok(unit)
