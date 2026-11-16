// ms: swap "@std/os/fs.ms"

import (
	Bytes from "@std/bytes.ms",
	Promise, promise from "@std/concurrency/promise.ms",
)

// Every file read is refused; every other name in `@std/os/fs.ms` keeps the original.
export fn read_file(path: String, max_bytes: Int? = none) Promise[Bytes]:
	message := f"read_file {path}: blocked by limits/no_files.ms"
	return promise(fn: error(Error(message.clone(), kind: "EACCES")))
