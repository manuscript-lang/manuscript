// ms: allow_effect std.fs.*

import write_file from "@std/os/fs.ms"

// ms: allow_effect std.fs.read
fn narrow(path: String) Unit!:
    try write_file(path, "x").wait()
    return ok(unit)

fn wide(path: String) Unit!:
    try write_file(path, "x").wait()
    return ok(unit)

export fn main() Int:
    return 0
