# conform: tags=diagnostics,modules,stdlib-fs,tier-io
# conform: phase=check
# conform: origin=pkg/build/filesystem_defaults_test.go:52 TestFilesystemExplicitFlagsKeepDirectDispatch
import filesystem from "@std/fs.ms"
fn explicit() Unit:
    let fs = filesystem()
    fs.write_file("", "", false)
    fs.copy_file("", "", true)
    fs.copy_tree("", "", false, max_entries: none, max_bytes: 3)
    fs.create_directory("", true)
    fs.remove("", false)
