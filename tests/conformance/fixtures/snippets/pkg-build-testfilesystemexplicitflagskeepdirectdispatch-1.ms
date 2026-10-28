# conform: tags=diagnostics,modules,stdlib-fs,tier-io
# conform: phase=check
# conform: origin=pkg/build/filesystem_defaults_test.go:52 TestFilesystemExplicitFlagsKeepDirectDispatch
import filesystem from "@std/fs.ms"

fn explicit() Unit:
    let fs = filesystem()
    let _ = fs.write_file("", "", false)
    let _ = fs.copy_file("", "", true)
    let _ = fs.copy_tree("", "", false, max_entries: none, max_bytes: 3)
    let _ = fs.create_directory("", true)
    let _ = fs.remove("", false)
