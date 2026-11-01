import open from "@std/os/fs.ms"

# A file handle has one owner: moving it into a list ends its use here.
fn reuse(path: String) Int!:
    let file = try open(path, "r", 0)
    let owners = [file]
    let info = try file.stat()
    return ok(info.size + owners.length())
