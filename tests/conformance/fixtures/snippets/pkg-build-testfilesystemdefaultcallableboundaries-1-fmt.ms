# conform: tags=formatter,generics,modules,parser,stdlib-bytes,stdlib-fs,tier-io
# conform: phase=parse
# conform: origin=pkg/build/filesystem_defaults_test.go:17 TestFilesystemDefaultCallableBoundaries
from "@std/fs.ms" import filesystem, FileSystemError
from "@std/bytes.ms" import Bytes

def forward[T](item: T) -> T: item
