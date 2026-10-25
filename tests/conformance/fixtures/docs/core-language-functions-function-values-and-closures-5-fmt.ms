# conform: tags=closures,formatter,modules,parser,stdlib-bytes,stdlib-fs,strings,tier-io,try-result,with-cleanup
# conform: phase=parse
# conform: origin=documentation/core-language/functions/function-values-and-closures.md:83
from "@std/fs.ms" import filesystem, FileSystemError
from "@std/bytes.ms" import Bytes

def notes_reader(path: String) -> Callable[[], Result[Bytes, FileSystemError]]:
    return lambda:
        with let file = try filesystem().open(path: path, flags: "r", mode: 0):
            return file.read_file(max_bytes: 1048576)
