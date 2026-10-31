# conform: tags=closures,formatter,modules,parser,stdlib-bytes,stdlib-fs,strings,tier-io,try-result,scope-cleanup
# conform: phase=parse
# conform: origin=documentation/core-language/functions/function-values-and-closures.md:83
import FileSystemError, open from "@std/fs.ms"
import Bytes from "@std/bytes.ms"

fn notes_reader(path: String) fn() Result[Bytes, FileSystemError]:
    return fn:
        let file = try open(path: path, flags: "r", mode: 0)
        return file.read_file(max_bytes: 1048576)
