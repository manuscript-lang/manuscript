# conform: tags=control-flow,modules,stdlib-fs,tier-io,try-result
# conform: phase=run
# conform: origin=tests/e2e/fs_remove_test.go:17 TestFileSystemRemoveProtectsWorkingDirectory
import filesystem, FileSystemError from "@std/fs.ms"

export fn main() Int:
    let fs = filesystem()
    let invalid: Unit!FileSystemError = error(FileSystemError.InvalidInput)
    if fs.remove(path: "", recursive: true) != invalid: return 1
    if fs.remove(path: ".", recursive: true) != invalid: return 2
    if fs.remove(path: "child/..", recursive: true) != invalid: return 3

    if let base = fs.canonicalize("."):
        if fs.remove(path: base, recursive: true) != invalid: return 4
    else:
        return 8

    if fs.rename(source: "", destination: "moved") != invalid: return 5
    if fs.rename(source: "sentinel", destination: "") != invalid: return 6
    if fs.remove(path: "child", recursive: true).is_error(): return 7

    return 0
