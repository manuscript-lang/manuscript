# conform: tags=closures,diagnostics,modules,stdlib-bytes,stdlib-fs,strings,tier-io,try-result,scope-cleanup
# conform: phase=check
# conform: origin=documentation/core-language/functions/function-values-and-closures.md:83
from "@std/fs.ms" import filesystem, FileSystemError
from "@std/bytes.ms" import Bytes

def notes_reader(path: String) -> Callable[[], Result[Bytes, FileSystemError]]:
    return lambda:
        let file = try filesystem().open(path: path, flags: "r", mode: 0)
        return file.read_file(max_bytes: 1048576)
