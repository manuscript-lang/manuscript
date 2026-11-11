// conform: tags=diagnostics
// conform: phase=check
import filesystem from "@std/os/fs.ms"
fn classify(path: String) String:
    match filesystem().stat(path: path, follow_links: true):
        error(NotFound): return "missing"
        ok(_): return "exists"
