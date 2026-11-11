// conform: tags=diagnostics
// conform: phase=check
import filesystem from "@std/os/fs.ms"
fn explicit() Unit:
    fs := filesystem()
    fs.write_file("", "", false)
    fs.copy_file("", "", true)
    fs.copy_tree("", "", false, max_entries: none, max_bytes: 3)
    fs.create_directory("", true)
    fs.remove("", false)
