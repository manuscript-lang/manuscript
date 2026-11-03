// conform: tags=control-flow,modules,stdlib-fs,tier-io,try-result
// conform: phase=run
// conform: origin=tests/e2e/fs_remove_test.go:17 TestFileSystemRemoveProtectsWorkingDirectory
import canonicalize, remove, rename from "@std/os/fs.ms"

// The failure names the path after the status words, so only its kind is compared.
fn refused(outcome: Unit!) Bool:
    return outcome.is_error() and outcome.err().kind == ErrorCategory.InvalidInput

export fn main() Int:
    if not refused(remove(path: "", recursive: true)): return 1
    if not refused(remove(path: ".", recursive: true)): return 2
    if not refused(remove(path: "child/..", recursive: true)): return 3

    if let base = canonicalize("."):
        if not refused(remove(path: base, recursive: true)): return 4
    else:
        return 8

    if not refused(rename(source: "", destination: "moved")): return 5
    if not refused(rename(source: "sentinel", destination: "")): return 6
    if remove(path: "child", recursive: true).is_error(): return 7

    return 0
