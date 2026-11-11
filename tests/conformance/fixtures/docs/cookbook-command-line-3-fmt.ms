// conform: tags=control-flow,formatter,modules,parser,stdlib-fs,stdlib-io,stdlib-process,tier-io,try-result
// conform: phase=parse
// conform: origin=documentation/learn/common-tasks.md:63
import arguments from "@std/os/env.ms"
import read_file from "@std/os/fs.ms"
import stdout from "@std/io/io.ms"

fn run() Result[Unit, Error]:
    path := arguments().first().ok_or(
        Error("filesystem: invalid input", kind: "EINVAL")
    )?
    text := read_file(path, max_bytes: 1048576).wait()? | .decode_utf8().ok_or(
        Error("filesystem: invalid data", kind: "EBADMSG")
    )?
    stdout().write(text)?
    return stdout().flush()

fn main() Unit!:
    run()?
