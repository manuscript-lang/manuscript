# conform: tags=formatter,modules,parser,stdlib-fs,tier-io
# conform: phase=parse
# conform: origin=pkg/build/filesystem_defaults_test.go:52 TestFilesystemExplicitFlagsKeepDirectDispatch
from "@std/fs.ms" import filesystem

def explicit() -> Unit:
    let fs = filesystem()
    fs.write_file("", "", False)
    fs.copy_file("", "", True)
    fs.copy_tree("", "", False, max_entries: none, max_bytes: 3)
    fs.create_directory("", True)
    fs.remove("", False)
