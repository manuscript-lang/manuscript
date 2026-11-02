# conform: tags=closures,diagnostics,modules,stdlib-bytes,stdlib-fs,strings,tier-io,try-result,scope-cleanup
# conform: phase=check
# conform: origin=documentation/core-language/functions/function-values-and-closures.md:83
import open from "@std/os/fs.ms"
import Bytes from "@std/bytes.ms"

fn notes_reader(path: String) fn() Result[Bytes, Error]:
    return fn:
        let file = try open(path: path, flags: "r", mode: 0)
        return file.read_file(max_bytes: 1048576)
