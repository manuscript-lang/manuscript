// conform: tags=diagnostics,formatter,generics,modules,stdlib-bytes,stdlib-fs,tier-io
// conform: phase=check,parse
// conform: origin=pkg/build/filesystem_defaults_test.go:17 TestFilesystemDefaultCallableBoundaries
import Bytes from "@std/bytes.ms"

fn forward[T](hold item T) &T => item
// expect-exit: 0
