# conform: tags=closures,diagnostics,modules,stdlib-bytes,stdlib-fs,strings,tier-io,try-result,with-cleanup
# conform: phase=check
# conform: origin=documentation/core-language/functions/function-values-and-closures.md:83
import {filesystem, FileSystemError} from "@std/fs.ms"
import Bytes from "@std/bytes.ms"

fn notes_reader(path: String) fn() Result[Bytes, FileSystemError]:
    return fn:
        with let file = try filesystem().open(path: path, flags: "r", mode: 0):
            return file.read_file(max_bytes: 1048576)
