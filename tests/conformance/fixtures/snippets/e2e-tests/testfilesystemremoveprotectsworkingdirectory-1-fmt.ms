# conform: tags=control-flow,formatter,modules,parser,stdlib-fs,tier-io,try-result
# conform: phase=parse
# conform: origin=tests/e2e/fs_remove_test.go:17 TestFileSystemRemoveProtectsWorkingDirectory
import canonicalize, remove, rename from "@std/os/fs.ms"

export fn main() Int:
    let invalid: Unit! = error(Error("filesystem: invalid input", kind: ErrorCategory.InvalidInput))
    if remove(path: "", recursive: true) != invalid: return 1
    if remove(path: ".", recursive: true) != invalid: return 2
    if remove(path: "child/..", recursive: true) != invalid: return 3

    if let base = canonicalize("."):
        if remove(path: base, recursive: true) != invalid: return 4
    else:
        return 8

    if rename(source: "", destination: "moved") != invalid: return 5
    if rename(source: "sentinel", destination: "") != invalid: return 6
    if remove(path: "child", recursive: true).is_error(): return 7

    return 0
