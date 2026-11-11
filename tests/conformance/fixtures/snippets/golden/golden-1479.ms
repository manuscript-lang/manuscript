// conform: tags=diagnostics
// conform: phase=check
import filesystem, FileSystemError from "@std/os/fs.ms"

export fn main() Int:
    fs := filesystem()
    invalid: Result[Unit, FileSystemError] := error(FileSystemError.InvalidInput)
    if fs.remove(path: "", recursive: true) != invalid: return 1
    if fs.remove(path: ".", recursive: true) != invalid: return 2
    if fs.remove(path: "child/..", recursive: true) != invalid: return 3
    if base := fs.canonicalize("."):
        if fs.remove(path: base, recursive: true) != invalid: return 4
    else:
        return 8
    if fs.rename(source: "", destination: "moved") != invalid: return 5
    if fs.rename(source: "sentinel", destination: "") != invalid: return 6
    if fs.remove(path: "child", recursive: true).is_error(): return 7
    return 0
