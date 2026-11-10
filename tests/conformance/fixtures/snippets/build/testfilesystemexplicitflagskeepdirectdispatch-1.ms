// conform: tags=diagnostics,modules,stdlib-fs,tier-io
// conform: phase=check
// conform: origin=pkg/build/filesystem_defaults_test.go:52 TestFilesystemExplicitFlagsKeepDirectDispatch
import copy, CopyOptions, create_directory, remove, write_file from "@std/os/fs.ms"

fn explicit() Unit:
    _ := write_file("", "", false).wait()
    _ := copy("", "", CopyOptions(replace: true))
    _ := copy("", "", CopyOptions(recursive: true, max_bytes: 3))
    _ := create_directory("", true)
    _ := remove("", false)
