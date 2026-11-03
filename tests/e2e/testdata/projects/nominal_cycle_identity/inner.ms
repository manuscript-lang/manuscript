import Closeable from "@std/core.ms"
import write_file from "@std/os/fs.ms"

export type Door:
    path: String

impl Closeable for Door:
    var fn close() Unit!:
        try write_file(self.path, "1", true).wait()
        return ok(unit)

export type Node:
    door: Door

export fn make_inner(path: String) Node:
    return Node(Door(path))
