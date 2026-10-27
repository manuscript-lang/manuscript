from "@std/fs.ms" import filesystem

# A file handle has one owner: moving it into a list ends its use here.
def reuse(path: String) -> Result[Int, Error]:
    let file = try filesystem().open(path, "r", 0)
    let owners = [file]
    let info = try file.stat()
    return ok(info.size + owners.length())
