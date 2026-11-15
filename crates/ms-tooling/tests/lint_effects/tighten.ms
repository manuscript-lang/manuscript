// ms: allow_effect std.fs.*

import write_file from "@std/os/fs.ms"

// ms: allow_effect std.fs.read
fn narrow(path: String) Void!:
    write_file(path, "x").wait()?

fn wide(path: String) Void!:
    write_file(path, "x").wait()?

fn main() Void:
    return
