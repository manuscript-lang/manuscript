# conform: tags=closures,control-flow,faults,formatter,generics,interpolation,match,modules,mutation,optional,parser,stdlib-bytes,stdlib-errors,stdlib-fs,stdlib-io,stdlib-testing,testing,tier-io,try-result,scope-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/fs.ms
import expect_equal, expect_false, expect_ok, fail from "@std/test/test.ms"
import (
    FileHandle,
    GlobOptions,
    PathEntry,
    create_directory,
    glob,
    glob_entries,
    list,
    open,
    read_file,
    remove,
    stat,
    temporary,
    write_file
) from "@std/os/fs.ms"
import read_all, open_read from "@std/io/io.ms"
import Bytes from "@std/bytes.ms"

fn expect_fs_error[T](outcome: T!, expected: Error) Unit!:
    match outcome:
        ok(_): return error(Error("filesystem misuse succeeded"))
        error(cause):
            if cause != expected: return error(Error("wrong filesystem error"))

    return ok(unit)

test "glob queries reuse patterns without changing hidden paths limits or callbacks":
    let temporary = temporary("manuscript-glob-") | try expect_ok
    let root = temporary.path()
    create_directory(path: "{root}/sub", recursive: false) | try expect_ok
    for name in ["a.txt", "b.md", ".hidden.txt", "sub/c.txt"]:
        write_file(path: "{root}/{name}", data: "", replace: false) | try expect_ok

    let matches = glob(path: root, pattern: "**/*.\{txt,md\}") | try expect_ok
    matches | try expect_equal(["a.txt", "b.md", "sub/c.txt"])
    glob(path: root, pattern: "**/*.\{txt,md\}", max_entries: 2) | try expect_fs_error(
        Error("filesystem: limit exceeded", kind: ErrorCategory.LimitExceeded)
    )
    glob(path: root, pattern: "\{a.txt,[\}") | try expect_fs_error(
        Error("filesystem: invalid input", kind: ErrorCategory.InvalidInput)
    )

    let options = GlobOptions(
        patterns: ["*.txt"], exclude: ["sub/**"], follow_links: false
    )
    let entries = (
        try expect_ok(
            glob_entries(
                path: root, options: options.clone(),
                exclude: fn(entry: PathEntry) Bool: entry.path == "missing.txt"
            )
        )
    )
    entries.length() | try expect_equal(1)
    entries.get(0).path | try expect_equal("a.txt")
    options.patterns | try expect_equal(["*.txt"])

test "ordinary filesystem misuse retains typed cases":
    let temporary = temporary("manuscript-errors-") | try expect_ok
    let directory = "{temporary.path()}/directory"
    let file = "{temporary.path()}/file"
    let _created = create_directory(path: directory, recursive: false) | try expect_ok
    let _child = write_file(path: "{directory}/child", data: "x", replace: false) | try expect_ok
    let _written = write_file(path: file, data: "abc", replace: false) | try expect_ok
    remove(path: directory, recursive: false) | try expect_fs_error(
        Error("filesystem: directory not empty", kind: ErrorCategory.Other)
    )
    list(path: file) | try expect_fs_error(
        Error("filesystem: invalid input", kind: ErrorCategory.InvalidInput)
    )
    read_file(path: directory) | try expect_fs_error(
        Error("filesystem: invalid input", kind: ErrorCategory.InvalidInput)
    )
    create_directory(path: file, recursive: false) | try expect_fs_error(
        Error("filesystem: already exists", kind: ErrorCategory.AlreadyExists)
    )

    var reader = open(path: file, flags: "r", mode: 384) | try expect_ok
    reader.write(
        "x"
    ) | try expect_fs_error(
        Error("I/O: invalid input", kind: ErrorCategory.InvalidInput)
    )
    reader.seek(
        offset: -1, origin: 0
    ) | try expect_fs_error(
        Error("filesystem: invalid input", kind: ErrorCategory.InvalidInput)
    )
    reader.seek(
        offset: 0, origin: 3
    ) | try expect_fs_error(
        Error("filesystem: invalid input", kind: ErrorCategory.InvalidInput)
    )
    try reader.close()

    let writer = open(path: file, flags: "a", mode: 384) | try expect_ok
    writer.read(
        1
    ) | try expect_fs_error(
        Error("I/O: invalid input", kind: ErrorCategory.InvalidInput)
    )
    writer.read_file() | try expect_fs_error(
        Error("filesystem: invalid input", kind: ErrorCategory.InvalidInput)
    )

test "filesystem scoped temporary directories and bounded file reads":
    var directory = ""
    var temporary = temporary("manuscript-stdlib-") | try expect_ok
    directory = temporary.path()

    let path = "{directory}/data.txt"
    let _written = write_file(path: path, data: "hello", replace: false) | try expect_ok
    read_file(path: path, max_bytes: 5) | try expect_ok | try expect_equal(
        "hello".to_bytes()
    )

    let limited: Bytes! = error(
        Error("filesystem: limit exceeded", kind: ErrorCategory.LimitExceeded)
    )
    read_file(path: path, max_bytes: 4) | try expect_equal(limited)

    let exists: Unit! = error(
        Error("filesystem: already exists", kind: ErrorCategory.AlreadyExists)
    )
    ((write_file(path: path, data: "changed", replace: false) != exists)) | try expect_false
    (stat(path: path, follow_links: true) | try expect_ok).size | try expect_equal(5)
    (list(path: directory) | try expect_ok).length() | try expect_equal(1)

    let input = open_read(path) | try expect_ok
    (input.read(5) | try expect_ok).get() | try expect_equal("hello".to_bytes())
    try temporary.close()

    match stat(path: directory, follow_links: true):
        ok(_): return fail("temporary directory not removed")
        error(cause):
            try expect_equal(
                cause,
                Error(
                    "filesystem: file or directory not found",
                    kind: ErrorCategory.NotFound
                )
            )

test "file handles positional I/O stream adapters and closed errors":
    let temporary = temporary("manuscript-handles-") | try expect_ok
    let path = "{temporary.path()}/data.txt"
    let _written = write_file(path: path, data: "abcdef", replace: false) | try expect_ok
    var handle = open(path: path, flags: "r+", mode: 384) | try expect_ok
    handle.read_at(offset: 2, max_bytes: 2) | try expect_ok | try expect_equal(
        "cd".to_bytes()
    )
    handle.write_at(offset: 1, data: "XY") | try expect_ok

    let _resized = handle.truncate(4) | try expect_ok
    (handle.stat() | try expect_ok).size | try expect_equal(4)

    let _sought = handle.seek(offset: 0, origin: 0) | try expect_ok
    handle.read_lines(
        max_bytes: -1
    ) | try expect_fs_error(
        Error("filesystem: invalid input", kind: ErrorCategory.InvalidInput)
    )
    handle.read_lines(
        max_lines: -1
    ) | try expect_fs_error(
        Error("filesystem: invalid input", kind: ErrorCategory.InvalidInput)
    )
    read_all(input: handle.reader()) | try expect_ok | try expect_equal(
        "aXYd".to_bytes()
    )
    try handle.close()

    let closed: Bytes! = error(
        Error("filesystem: resource is closed", kind: ErrorCategory.Closed)
    )
    handle.read_at(offset: 0, max_bytes: 1) | try expect_equal(closed)
    try handle.close()

test "empty paths are rejected instead of resolving to the working directory":
    let invalid: Unit! = error(
        cause: Error(
            "filesystem: invalid input", kind: ErrorCategory.InvalidInput
        )
    )
    remove(path: "", recursive: true) | try expect_equal(invalid)
    create_directory(path: "", recursive: true) | try expect_equal(invalid)
    write_file(path: "", data: "x", replace: true) | try expect_equal(invalid)

    match stat(path: "", follow_links: true):
        ok(_): return fail("stat empty path")
        error(cause):
            try expect_equal(
                cause,
                Error(
                    "filesystem: invalid input", kind: ErrorCategory.InvalidInput
                )
            )
