# conform: tags=formatter,modules,parser,stdlib-fs,tier-io
# conform: phase=parse
# conform: origin=pkg/build/filesystem_defaults_test.go:52 TestFilesystemExplicitFlagsKeepDirectDispatch
import copy_file, copy_tree, create_directory, remove, write_file from "@std/fs.ms"

fn explicit() Unit:
    let _ = write_file("", "", false)
    let _ = copy_file("", "", true)
    let _ = copy_tree("", "", false, max_entries: none, max_bytes: 3)
    let _ = create_directory("", true)
    let _ = remove("", false)
