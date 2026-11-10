import (
    expect_equal, expect_false, expect_ok, fail from "@std/test/test.ms",
    GlobOptions,
    OpenMode,
    OpenOptions,
    PathEntry,
    Seek,
    copy,
    create_directory,
    glob,
    list,
    open,
    read_file,
    remove,
    rename,
    stat,
    temporary,
    write_file from "@std/os/fs.ms",
    read_all from "@std/io/streams.ms",
    Bytes from "@std/bytes.ms",
)

fn expect_fs_error[T](outcome: T!, expected: Error) Unit!:
    match outcome:
        ok(_): return error(Error("filesystem misuse succeeded"))
        error(cause):
            // A failure names the path after the status words: "filesystem: <failure>: <path>".
            let named = cause.message.starts_with("{expected.message}: ")
            if (
                cause.kind != expected.kind
                or (cause.message != expected.message and not named)
            ): return error(Error("wrong filesystem error: {cause}"))

    return ok(unit)

test "glob queries reuse patterns without changing hidden paths limits or callbacks":
    let temporary = temporary("manuscript-glob-") | try expect_ok
    let root = temporary.path()
    create_directory(path: "{root}/sub", recursive: false) | try expect_ok
    for name in ["a.txt", "b.md", ".hidden.txt", "sub/c.txt"]:
        write_file(path: "{root}/{name}", data: "", replace: false).wait() | try expect_ok

    let all = GlobOptions(patterns: ["**/*.\{txt,md\}"])
    let matches = glob(path: root, options: all.clone()) | try expect_ok
    matches.map(fn e: e.path.clone()) | try expect_equal(["a.txt", "b.md", "sub/c.txt"])
    glob(
        path: root, options: GlobOptions(patterns: ["**/*.\{txt,md\}"], max_results: 2)
    ) | try expect_fs_error(Error("filesystem: limit exceeded", kind: "EOVERFLOW"))
    glob(path: root, options: GlobOptions(patterns: ["\{a.txt,[\}"])) | try expect_fs_error(
        Error("filesystem: invalid input", kind: "EINVAL")
    )

    let options = GlobOptions(patterns: ["*.txt"], exclude: ["sub/**"])
    let entries = (
        try expect_ok(
            glob(
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
    let _child = write_file(path: "{directory}/child", data: "x", replace: false).wait() | try expect_ok
    let _written = write_file(path: file, data: "abc", replace: false).wait() | try expect_ok
    remove(path: directory, recursive: false) | try expect_fs_error(
        Error("filesystem: directory not empty", kind: "ENOTEMPTY")
    )
    list(path: file) | try expect_fs_error(
        Error("filesystem: invalid input", kind: "EINVAL")
    )
    read_file(path: directory).wait() | try expect_fs_error(
        Error("filesystem: invalid input", kind: "EINVAL")
    )
    create_directory(path: file, recursive: false) | try expect_fs_error(
        Error("filesystem: already exists", kind: "EEXIST")
    )

    var reader = open(file, OpenMode.Read, OpenOptions(permissions: 384)) | try expect_ok
    reader.write("x") | try expect_fs_error(Error("I/O: invalid input", kind: "EINVAL"))
    reader.seek(
        offset: -1, origin: Seek.Start
    ) | try expect_fs_error(Error("filesystem: invalid input", kind: "EINVAL"))
    try reader.close()

    let writer = open(file, OpenMode.Append, OpenOptions(permissions: 384)) | try expect_ok
    writer.read(1) | try expect_fs_error(Error("I/O: invalid input", kind: "EINVAL"))
    writer.read_file() | try expect_fs_error(
        Error("filesystem: invalid input", kind: "EINVAL")
    )

test "filesystem scoped temporary directories and bounded file reads":
    var directory = ""
    var temporary = temporary("manuscript-stdlib-") | try expect_ok
    directory = temporary.path()

    let path = "{directory}/data.txt"
    let _written = write_file(path: path, data: "hello", replace: false).wait() | try expect_ok
    read_file(path: path, max_bytes: 5).wait() | try expect_ok | try expect_equal(
        "hello".to_bytes()
    )
    read_file(path: path, max_bytes: 4).wait() | try expect_fs_error(
        Error("filesystem: limit exceeded", kind: "EOVERFLOW")
    )
    write_file(path: path, data: "changed", replace: false).wait() | try expect_fs_error(
        Error("filesystem: already exists", kind: "EEXIST")
    )
    (stat(path: path) | try expect_ok).size | try expect_equal(5)
    (list(path: directory) | try expect_ok).length() | try expect_equal(1)

    let opened = open(path, OpenMode.Read) | try expect_ok
    var input = opened.reader() | try expect_ok
    (input.next() | try expect_ok).get() | try expect_equal("hello".to_bytes())
    try temporary.close()
    stat(path: directory) | try expect_fs_error(
        Error("filesystem: file or directory not found", kind: "ENOENT")
    )

test "file handles positional I/O stream adapters and closed errors":
    let temporary = temporary("manuscript-handles-") | try expect_ok
    let path = "{temporary.path()}/data.txt"
    let _written = write_file(path: path, data: "abcdef", replace: false).wait() | try expect_ok
    var handle = open(path, OpenMode.ReadWrite, OpenOptions(permissions: 384)) | try expect_ok
    handle.read_at(offset: 2, max_bytes: 2) | try expect_ok | try expect_equal(
        "cd".to_bytes()
    )
    handle.write_at(offset: 1, data: "XY") | try expect_ok

    let _resized = handle.truncate(4) | try expect_ok
    (handle.stat() | try expect_ok).size | try expect_equal(4)

    let _sought = handle.seek(offset: 0, origin: Seek.Start) | try expect_ok
    let contents = read_all(input: try handle.reader(), max_bytes: none) | try expect_ok
    contents | try expect_equal("aXYd".to_bytes())
    try handle.close()

    let closed: Bytes! = error(Error("filesystem: resource is closed", kind: "EBADF"))
    handle.read_at(offset: 0, max_bytes: 1) | try expect_equal(closed)
    try handle.close()

test "empty paths are rejected instead of resolving to the working directory":
    let invalid: Unit! = error(
        cause: Error("filesystem: invalid input", kind: "EINVAL")
    )
    remove(path: "", recursive: true) | try expect_equal(invalid)
    create_directory(path: "", recursive: true) | try expect_equal(invalid)
    write_file(path: "", data: "x", replace: true).wait() | try expect_equal(invalid)

    match stat(path: ""):
        ok(_): return fail("stat empty path")
        error(cause):
            try expect_equal(cause, Error("filesystem: invalid input", kind: "EINVAL"))

test "rename and copy failures name source and destination":
    let temporary = temporary("manuscript-pair-") | try expect_ok
    let root = temporary.path()
    let from = "{root}/missing"
    let to = "{root}/target"
    let expected = "filesystem: file or directory not found: {from} -> {to}"

    match rename(from, to):
        ok(_): return fail("rename of a missing file succeeded")
        error(cause): cause.message | try expect_equal(expected)

    match copy(from, to):
        ok(_): return fail("copy of a missing file succeeded")
        error(cause): cause.message | try expect_equal(expected)
