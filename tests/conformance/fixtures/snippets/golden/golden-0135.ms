// conform: tags=diagnostics
// conform: phase=check
import filesystem, FileSystemError from "@std/os/fs.ms"
import Bytes from "@std/bytes.ms"
fn forward[T](item: T) T: item
