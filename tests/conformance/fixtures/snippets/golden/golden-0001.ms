// conform: tags=diagnostics
// conform: phase=check
import filesystem from "@std/os/fs.ms"
fn use(path: String) Int:
    match filesystem().stat(path: path, follow_links: true):
        error(NotFound): return 1
        ok(_): return 0
