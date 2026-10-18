import {expect_equal, expect_false, expect_ok, fail} from "@std/testing.ms"
import TextError from "@std/errors.ms"
import {filesystem, FileSystemError, FileHandle, GlobOptions, PathEntry} from "@std/fs.ms"
import {files, read_all, IoError} from "@std/io.ms"
import Bytes from "@std/bytes.ms"

fn expect_fs_error[T](
    outcome: Result[T, FileSystemError],
    expected: FileSystemError
) -> Result[Unit, Error]:
    match outcome:
        ok(_): return error(TextError.Text("filesystem misuse succeeded"))
        error(cause):
            if cause != expected: return error(TextError.Text("wrong filesystem error"))

    return ok(unit)

test "glob queries reuse patterns without changing hidden paths limits or callbacks":
    let fs = filesystem()

    with temporary = (fs.temporary("manuscript-glob-") | try expect_ok):
        let root = temporary.path()
        (fs.create_directory(path: "{root}/sub", recursive: false) | try expect_ok)
        for name in ["a.txt", "b.md", ".hidden.txt", "sub/c.txt"]:
            (
                fs.write_file(
                    path: "{root}/{name}",
                    data: "".to_bytes(),
                    replace: false
                ) | try expect_ok
            )
        let matches = (fs.glob(path: root, pattern: "**/*.\{txt,md\}") | try expect_ok)
        matches | try expect_equal(expected: ["a.txt", "b.md", "sub/c.txt"])
        (
            fs.glob(
                path: root,
                pattern: "**/*.\{txt,md\}",
                max_entries: 2
            ) | try expect_fs_error(expected: FileSystemError.LimitExceeded)
        )
        (
            fs.glob(
                path: root,
                pattern: "\{a.txt,[\}"
            ) | try expect_fs_error(expected: FileSystemError.InvalidInput)
        )
        let options = GlobOptions(
            patterns: ["*.txt"],
            exclude: ["sub/**"],
            follow_links: false
        )
        let entries = (
            try expect_ok(
                fs.glob_entries(
                    path: root,
                    options: options,
                    exclude: some(
                        fn(entry: PathEntry) -> Bool:
                            if entry.path == ".": options.patterns.set(0, "*.md")
                            return false
                    )
                )
            )
        )
        entries.length() | try expect_equal(expected: 1)
        entries.at(0).unwrap().path | try expect_equal(expected: "b.md")

test "ordinary filesystem misuse retains typed cases":
    let fs = filesystem()

    with temporary = (fs.temporary("manuscript-errors-") | try expect_ok):
        let directory = "{temporary.path()}/directory"
        let file = "{temporary.path()}/file"
        let created = (
            fs.create_directory(
                path: directory,
                recursive: false
            ) | try expect_ok
        )
        let child = (
            fs.write_file(
                path: "{directory}/child",
                data: "x".to_bytes(),
                replace: false
            ) | try expect_ok
        )
        let written = (
            fs.write_file(
                path: file,
                data: "abc".to_bytes(),
                replace: false
            ) | try expect_ok
        )
        (
            fs.remove(
                path: directory,
                recursive: false
            ) | try expect_fs_error(expected: FileSystemError.NotEmpty)
        )
        (
            fs.list(path: file) | try expect_fs_error(
                expected: FileSystemError.InvalidInput
            )
        )
        (
            fs.read_file(path: directory) | try expect_fs_error(
                expected: FileSystemError.InvalidInput
            )
        )
        (
            fs.create_directory(
                path: file,
                recursive: false
            ) | try expect_fs_error(expected: FileSystemError.AlreadyExists)
        )

        with reader = (fs.open(path: file, flags: "r", mode: 384) | try expect_ok):
            (
                reader.write("x".to_bytes()) | try expect_fs_error(
                    expected: FileSystemError.InvalidInput
                )
            )
            (
                reader.seek(
                    offset: -1,
                    origin: 0
                ) | try expect_fs_error(expected: FileSystemError.InvalidInput)
            )
            (
                reader.seek(offset: 0, origin: 3) | try expect_fs_error(
                    expected: FileSystemError.InvalidInput
                )
            )

        with writer = (fs.open(path: file, flags: "a", mode: 384) | try expect_ok):
            (
                writer.read(1) | try expect_fs_error(
                    expected: FileSystemError.InvalidInput
                )
            )
            (
                writer.read_file() | try expect_fs_error(
                    expected: FileSystemError.InvalidInput
                )
            )

test "filesystem scoped temporary directories and bounded file reads":
    let fs = filesystem()
    var directory = ""

    with temporary = (fs.temporary("manuscript-stdlib-") | try expect_ok):
        directory = temporary.path()
        let path = "{directory}/data.txt"
        let written = (
            fs.write_file(
                path: path,
                data: "hello".to_bytes(),
                replace: false
            ) | try expect_ok
        )
        fs.read_file(path: path, max_bytes: 5) | try expect_ok | try expect_equal(
            expected: "hello".to_bytes()
        )
        let limited: Result[Bytes, FileSystemError] = error(
            FileSystemError.LimitExceeded
        )
        fs.read_file(path: path, max_bytes: 4) | try expect_equal(expected: limited)
        let exists: Result[Unit, FileSystemError] = error(FileSystemError.AlreadyExists)
        (
            (
                fs.write_file(
                    path: path,
                    data: "changed".to_bytes(),
                    replace: false
                ) != exists
            )
        ) | try expect_false
        (fs.stat(path: path, follow_links: true) | try expect_ok).size | try expect_equal(
            expected: 5
        )
        (fs.list(path: directory) | try expect_ok).length() | try expect_equal(
            expected: 1
        )
        with input = (files().open(path) | try expect_ok):
            (input.read(5) | try expect_ok).unwrap() | try expect_equal(
                expected: "hello".to_bytes()
            )

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
                path: path,
                data: "abcdef".to_bytes(),
                replace: false
            ) | try expect_ok
        )
        let handle = (fs.open(path: path, flags: "r+", mode: 384) | try expect_ok)

        with scoped = handle:
            handle.read_at(offset: 2, max_bytes: 2) | try expect_ok | try expect_equal(
                expected: "cd".to_bytes()
            )
            (handle.write_at(offset: 1, data: "XY".to_bytes()) | try expect_ok)
            let resized = (handle.truncate(4) | try expect_ok)
            (handle.stat() | try expect_ok).size | try expect_equal(expected: 4)
            let sought = (handle.seek(offset: 0, origin: 0) | try expect_ok)
            read_all(input: handle.reader()) | try expect_ok | try expect_equal(
                expected: "aXYd".to_bytes()
            )

        let closed: Result[Bytes, FileSystemError] = error(FileSystemError.Closed)
        handle.read_at(offset: 0, max_bytes: 1) | try expect_equal(expected: closed)
        handle.close()

test "empty paths are rejected instead of resolving to the working directory":
    let fs = filesystem()
    let invalid: Result[Unit, FileSystemError] = error(
        cause: FileSystemError.InvalidInput
    )
    fs.remove(path: "", recursive: true) | try expect_equal(expected: invalid)
    fs.create_directory(path: "", recursive: true) | try expect_equal(expected: invalid)
    fs.write_file(path: "", data: "x".to_bytes(), replace: true) | try expect_equal(
        expected: invalid
    )

    match fs.stat(path: "", follow_links: true):
        ok(_): return fail("stat empty path")
        error(cause):
            try expect_equal(cause, FileSystemError.InvalidInput)
