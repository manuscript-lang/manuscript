import read_file from "@std/os/fs.ms"
import Bytes from "@std/bytes.ms"

export fn load(path: String) Bytes!:
    return read_file(path).wait()

export fn greet(name: String) String:
    return "hi {name}"
