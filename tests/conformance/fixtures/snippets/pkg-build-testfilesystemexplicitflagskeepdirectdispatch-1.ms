# conform: tags=diagnostics,modules,stdlib-fs,tier-io
# conform: phase=check
# conform: origin=pkg/build/filesystem_defaults_test.go:52 TestFilesystemExplicitFlagsKeepDirectDispatch
from "@std/fs.ms" import filesystem

def explicit() -> Unit:
    let fs = filesystem()
    let _ = fs.write_file("", "", False)
    let _ = fs.copy_file("", "", True)
    let _ = fs.copy_tree("", "", False, max_entries: none, max_bytes: 3)
    let _ = fs.create_directory("", True)
    let _ = fs.remove("", False)
