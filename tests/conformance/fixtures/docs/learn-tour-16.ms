# conform: tags=diagnostics,modules,stdlib-fs,tier-io,try-result,scope-cleanup
# conform: phase=check
# conform: origin=documentation/learn/tour.md:312
import open, write_file_bytes from "@std/os/fs.ms"

fn copy_notes() Result[Unit, Error]:
    var source = try open("notes.txt", flags: "r", mode: 0)
    let contents = try source.read_file(max_bytes: 1048576)
    try write_file_bytes(path: "backup.txt", data: contents, replace: true)
    return ok(unit)
