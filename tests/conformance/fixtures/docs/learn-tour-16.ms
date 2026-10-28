# conform: tags=diagnostics,modules,stdlib-fs,tier-io,try-result,scope-cleanup
# conform: phase=check
# conform: origin=documentation/learn/tour.md:312
from "@std/fs.ms" import filesystem, FileSystemError

def copy_notes() -> Result[Unit, FileSystemError]:
    var source = try filesystem().open("notes.txt", flags: "r", mode: 0)
    let contents = try source.read_file(max_bytes: 1048576)
    try filesystem().write_file_bytes(path: "backup.txt", data: contents, replace: True)
    source.close()
    return ok(())
