# conform: tags=control-flow,diagnostics,modules,stdlib-fs,stdlib-process,tier-io,try-result
# conform: phase=check
# conform: origin=documentation/learn/common-tasks.md:94
from "@std/process.ms" import arguments
from "@std/fs.ms" import filesystem, FileSystemError

def run() -> Result[Unit, Error]:
    let path = try arguments().first().ok_or(FileSystemError.InvalidInput)
    return filesystem().write_file(path, "saved notes\n", replace: False)

export def main() -> Int:
    if run().is_error():
        return 1

    return 0
