# conform: tags=formatter,modules,parser,stdlib-fs,tier-io,try-result,with-cleanup
# conform: phase=parse
# conform: origin=documentation/learn/tour.md:312
import {filesystem, FileSystemError} from "@std/fs.ms"

fn copy_notes() Result[Unit, FileSystemError]:
    with source = try filesystem().open("notes.txt", flags: "r", mode: 0):
        let contents = try source.read_file(max_bytes: 1048576)
        try filesystem().write_file_bytes(
            path: "backup.txt", data: contents, replace: true
        )

    return ok(unit)
