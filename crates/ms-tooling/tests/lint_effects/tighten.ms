// ms: allow_effect std.fs.*

import write_file from "@std/os/fs.ms"

// ms: allow_effect std.fs.read
fn narrow(path: String) Unit!:
    try write_file(path, "x").wait()

fn wide(path: String) Unit!:
    try write_file(path, "x").wait()

fn main() Unit:
    return
