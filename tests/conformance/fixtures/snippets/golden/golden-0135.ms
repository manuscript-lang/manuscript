// conform: tags=diagnostics
// conform: phase=check
import (
	Bytes from "@std/bytes.ms",
	FileSystemError, filesystem from "@std/os/fs.ms",
)

fn forward[T](item T) T => item
