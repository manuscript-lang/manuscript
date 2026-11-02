# conform: tags=diagnostics,generics,modules,stdlib-bytes,stdlib-fs,tier-io
# conform: phase=check
# conform: origin=pkg/build/filesystem_defaults_test.go:17 TestFilesystemDefaultCallableBoundaries
import FileSystemError from "@std/os/fs.ms"
import Bytes from "@std/bytes.ms"

fn forward[T](item: T) T: item
