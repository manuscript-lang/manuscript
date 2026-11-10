import OpenMode, open from "@std/os/fs.ms"

// A file handle has one owner: moving it into a list ends its use here.
fn reuse(path: String) Int!:
    file := try open(path, OpenMode.Read)
    owners := [file]
    info := try file.stat()
    return ok(info.size + owners.length())
