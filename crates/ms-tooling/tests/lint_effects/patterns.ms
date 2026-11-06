// ms: allow_effect *.read

import Bytes from "@std/bytes.ms"
import read_file, write_file from "@std/os/fs.ms"

fn r(path: String) Bytes!:
    return read_file(path).wait()

fn w(path: String) Unit!:
    return write_file(path, "x").wait()

export fn main() Int:
    return 0
