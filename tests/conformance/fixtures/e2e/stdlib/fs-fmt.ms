# conform: tags=closures,control-flow,faults,formatter,generics,interpolation,match,modules,mutation,optional,parser,stdlib-bytes,stdlib-errors,stdlib-fs,stdlib-io,stdlib-testing,testing,tier-io,try-result,with-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/fs.ms
import {expect_equal, expect_false, expect_ok, fail} from "@std/testing.ms"
import TextError from "@std/core.ms"
import {filesystem, FileSystemError, FileHandle, GlobOptions, PathEntry} from "@std/fs.ms"
import {files, read_all, IoError} from "@std/io.ms"
import Bytes from "@std/bytes.ms"

fn expect_fs_error[T](
    outcome: Result[T, FileSystemError],
    expected: FileSystemError
) Result[Unit, Error]:
    match outcome:
        ok(_): return error(TextError("filesystem misuse succeeded"))
        error(cause):
            if cause != expected: return error(TextError("wrong filesystem error"))

    return ok(unit)

test "glob queries reuse patterns without changing hidden paths limits or callbacks":
    let fs = filesystem()

    with temporary = (fs.temporary("manuscript-glob-") | try expect_ok):
        let root = temporary.path()
        (fs.create_directory(path: "{root}/sub", recursive: false) | try expect_ok)
        for name in ["a.txt", "b.md", ".hidden.txt", "sub/c.txt"]:
            (
                fs.write_file(
                    path: "{root}/{name}", data: "", replace: false
                ) | try expect_ok
            )

        let matches = (fs.glob(path: root, pattern: "**/*.\{txt,md\}") | try expect_ok)
        matches | try expect_equal(["a.txt", "b.md", "sub/c.txt"])
        (
            fs.glob(
                path: root, pattern: "**/*.\{txt,md\}", max_entries: 2
            ) | try expect_fs_error(FileSystemError.LimitExceeded)
        )
        (
            fs.glob(
                path: root, pattern: "\{a.txt,[\}"
            ) | try expect_fs_error(FileSystemError.InvalidInput)
        )

        let options = GlobOptions(
            patterns: ["*.txt"], exclude: ["sub/**"], follow_links: false
        )
        let entries = (
            try expect_ok(
                fs.glob_entries(
                    path: root,
                    options: options.clone(),
                    exclude: some(
                        fn(entry: PathEntry) Bool: entry.path == "missing.txt"
                    )
                )
            )
        )
        entries.length() | try expect_equal(1)
        entries.get(0).path | try expect_equal("a.txt")
        options.patterns | try expect_equal(["*.txt"])

test "ordinary filesystem misuse retains typed cases":
    let fs = filesystem()

    with temporary = (fs.temporary("manuscript-errors-") | try expect_ok):
        let directory = "{temporary.path()}/directory"
        let file = "{temporary.path()}/file"
        let created = (
            fs.create_directory(
                path: directory, recursive: false
            ) | try expect_ok
        )
        let child = (
            fs.write_file(
                path: "{directory}/child", data: "x", replace: false
            ) | try expect_ok
        )
        let written = (
            fs.write_file(
                path: file, data: "abc", replace: false
            ) | try expect_ok
        )
        (
            fs.remove(
                path: directory, recursive: false
            ) | try expect_fs_error(FileSystemError.NotEmpty)
        )
        (fs.list(path: file) | try expect_fs_error(FileSystemError.InvalidInput))
        (
            fs.read_file(path: directory) | try expect_fs_error(
                FileSystemError.InvalidInput
            )
        )
        (
            fs.create_directory(
                path: file, recursive: false
            ) | try expect_fs_error(FileSystemError.AlreadyExists)
        )

        with reader = (fs.open(path: file, flags: "r", mode: 384) | try expect_ok):
            (reader.write("x") | try expect_fs_error(FileSystemError.InvalidInput))
            (
                reader.seek(
                    offset: -1, origin: 0
                ) | try expect_fs_error(FileSystemError.InvalidInput)
            )
            (
                reader.seek(offset: 0, origin: 3) | try expect_fs_error(
                    FileSystemError.InvalidInput
                )
            )

        with writer = (fs.open(path: file, flags: "a", mode: 384) | try expect_ok):
            (writer.read(1) | try expect_fs_error(FileSystemError.InvalidInput))
            (writer.read_file() | try expect_fs_error(FileSystemError.InvalidInput))

test "filesystem scoped temporary directories and bounded file reads":
    let fs = filesystem()
    var directory = ""

    with temporary = (fs.temporary("manuscript-stdlib-") | try expect_ok):
        directory = temporary.path()

        let path = "{directory}/data.txt"
        let written = (
            fs.write_file(
                path: path, data: "hello", replace: false
            ) | try expect_ok
        )
        fs.read_file(path: path, max_bytes: 5) | try expect_ok | try expect_equal(
            "hello".to_bytes()
        )

        let limited: Result[Bytes, FileSystemError] = error(
            FileSystemError.LimitExceeded
        )
        fs.read_file(path: path, max_bytes: 4) | try expect_equal(limited)

        let exists: Result[Unit, FileSystemError] = error(FileSystemError.AlreadyExists)
        ((fs.write_file(path: path, data: "changed", replace: false) != exists)) | try expect_false
        (fs.stat(path: path, follow_links: true) | try expect_ok).size | try expect_equal(
            5
        )
        (fs.list(path: directory) | try expect_ok).length() | try expect_equal(1)
        with input = (files().open(path) | try expect_ok):
            (input.read(5) | try expect_ok).get() | try expect_equal("hello".to_bytes())

    match fs.stat(path: directory, follow_links: true):
        ok(_): return fail("temporary directory not removed")
        error(cause):
            try expect_equal(cause, FileSystemError.NotFound)

test "file handles positional I/O stream adapters and closed errors":
    let fs = filesystem()

    with temporary = (fs.temporary("manuscript-handles-") | try expect_ok):
        let path = "{temporary.path()}/data.txt"
        let written = (
            fs.write_file(
                path: path, data: "abcdef", replace: false
            ) | try expect_ok
        )
        let handle = (fs.open(path: path, flags: "r+", mode: 384) | try expect_ok)
        handle.read_at(offset: 2, max_bytes: 2) | try expect_ok | try expect_equal(
            "cd".to_bytes()
        )
        (handle.write_at(offset: 1, data: "XY") | try expect_ok)

        let resized = (handle.truncate(4) | try expect_ok)
        (handle.stat() | try expect_ok).size | try expect_equal(4)

        let sought = (handle.seek(offset: 0, origin: 0) | try expect_ok)
        read_all(input: handle.reader()) | try expect_ok | try expect_equal(
            "aXYd".to_bytes()
        )
        handle.close()

        let closed: Result[Bytes, FileSystemError] = error(FileSystemError.Closed)
        handle.read_at(offset: 0, max_bytes: 1) | try expect_equal(closed)
        handle.close()

test "empty paths are rejected instead of resolving to the working directory":
    let fs = filesystem()
    let invalid: Result[Unit, FileSystemError] = error(
        cause: FileSystemError.InvalidInput
    )
    fs.remove(path: "", recursive: true) | try expect_equal(invalid)
    fs.create_directory(path: "", recursive: true) | try expect_equal(invalid)
    fs.write_file(path: "", data: "x", replace: true) | try expect_equal(invalid)

    match fs.stat(path: "", follow_links: true):
        ok(_): return fail("stat empty path")
        error(cause):
            try expect_equal(cause, FileSystemError.InvalidInput)
