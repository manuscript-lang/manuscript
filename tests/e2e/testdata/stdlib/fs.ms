import {filesystem, FileSystemError, FileHandle, GlobOptions, PathEntry} from "@std/fs.ms"
import {files, read_all, IoError} from "@std/io.ms"
import Bytes from "@std/bytes.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

fn expect_fs_error[T](
    outcome: Result[T, FileSystemError],
    expected: FileSystemError
) Unit:
    if outcome.is_ok(): return panic("filesystem misuse succeeded")
    if outcome.unwrap_error() != expected: return panic("wrong filesystem error")

test "glob queries reuse patterns without changing hidden paths limits or callbacks":
    let fs = filesystem()

    with temporary = fs.temporary("manuscript-glob-") | value:
        let root = temporary.path()
        fs.create_directory(path: "{root}/sub", recursive: false) | value
        for name in ["a.txt", "b.md", ".hidden.txt", "sub/c.txt"]:
            fs.write_file(path: "{root}/{name}", data: "".to_bytes(), replace: false) | value
        let matches = fs.glob(path: root, pattern: "**/*.\{txt,md\}") | value
        if matches != ["a.txt", "b.md", "sub/c.txt"]: return panic("glob matches")

        fs.glob(path: root, pattern: "**/*.\{txt,md\}", max_entries: 2) | expect_fs_error(
            FileSystemError.LimitExceeded
        )
        fs.glob(path: root, pattern: "\{a.txt,[\}") | expect_fs_error(
            FileSystemError.InvalidInput
        )
        let options = GlobOptions(
            patterns: ["*.txt"],
            exclude: ["sub/**"],
            follow_links: false
        )
        let entries = fs.glob_entries(
            path: root,
            options: options,
            exclude: some(
                fn(entry: PathEntry) Bool:
                    if entry.path == ".": options.patterns.set(0, "*.md")
                    return false
            )
        ) | value
        if entries.length() != 1: return panic("glob_entries count")
        if entries.at(0).unwrap().path != "b.md": return panic(
            "callback changed pattern"
        )

test "ordinary filesystem misuse retains typed cases":
    let fs = filesystem()

    with temporary = fs.temporary("manuscript-errors-") | value:
        let directory = "{temporary.path()}/directory"
        let file = "{temporary.path()}/file"
        let created = fs.create_directory(path: directory, recursive: false) | value
        let child = fs.write_file(
            path: "{directory}/child",
            data: "x".to_bytes(),
            replace: false
        ) | value
        let written = fs.write_file(path: file, data: "abc".to_bytes(), replace: false) | value
        expect_fs_error(
            outcome: fs.remove(path: directory, recursive: false),
            expected: FileSystemError.NotEmpty
        )
        expect_fs_error(
            outcome: fs.list(path: file),
            expected: FileSystemError.InvalidInput
        )
        expect_fs_error(
            outcome: fs.read_file(path: directory),
            expected: FileSystemError.InvalidInput
        )
        expect_fs_error(
            outcome: fs.create_directory(path: file, recursive: false),
            expected: FileSystemError.AlreadyExists
        )

        with reader = fs.open(path: file, flags: "r", mode: 384) | value:
            expect_fs_error(
                outcome: reader.write("x".to_bytes()),
                expected: FileSystemError.InvalidInput
            )
            expect_fs_error(
                outcome: reader.seek(offset: -1, origin: 0),
                expected: FileSystemError.InvalidInput
            )
            expect_fs_error(
                outcome: reader.seek(offset: 0, origin: 3),
                expected: FileSystemError.InvalidInput
            )

        with writer = fs.open(path: file, flags: "a", mode: 384) | value:
            expect_fs_error(
                outcome: writer.read(1),
                expected: FileSystemError.InvalidInput
            )
            expect_fs_error(
                outcome: writer.read_file(),
                expected: FileSystemError.InvalidInput
            )

test "filesystem scoped temporary directories and bounded file reads":
    let fs = filesystem()
    var directory = ""

    with temporary = fs.temporary("manuscript-stdlib-") | value:
        directory = temporary.path()
        let path = "{directory}/data.txt"
        let written = fs.write_file(
            path: path,
            data: "hello".to_bytes(),
            replace: false
        ) | value
        if (value(fs.read_file(path: path, max_bytes: 5)) != "hello".to_bytes()): return panic(
            "read file"
        )

        let limited: Result[Bytes, FileSystemError] = error(
            FileSystemError.LimitExceeded
        )
        if fs.read_file(path: path, max_bytes: 4) != limited: return panic(
            "file byte limit"
        )

        let exists: Result[Unit, FileSystemError] = error(FileSystemError.AlreadyExists)
        if (
            fs.write_file(
                path: path,
                data: "changed".to_bytes(),
                replace: false
            ) != exists
        ): return panic("exclusive write")
        if value(fs.stat(path: path, follow_links: true)).size != 5: return panic(
            "file stat"
        )
        if value(fs.list(path: directory)).length() != 1: return panic("directory list")

        with input = value(files().open(path)):
            if value(input.read(5)).unwrap() != "hello".to_bytes(): return panic(
                "read-only Files host"
            )

    let removed = fs.stat(path: directory, follow_links: true)
    if removed.is_ok(): return panic("temporary directory not removed")
    if removed.unwrap_error() != FileSystemError.NotFound: return panic(
        "temporary cleanup error"
    )

test "file handles positional I/O stream adapters and closed errors":
    let fs = filesystem()

    with temporary = fs.temporary("manuscript-handles-") | value:
        let path = "{temporary.path()}/data.txt"
        let written = fs.write_file(
            path: path,
            data: "abcdef".to_bytes(),
            replace: false
        ) | value
        let handle = fs.open(path: path, flags: "r+", mode: 384) | value

        with scoped = handle:
            if (value(handle.read_at(offset: 2, max_bytes: 2)) != "cd".to_bytes()): return panic(
                "positional read"
            )

            handle.write_at(offset: 1, data: "XY".to_bytes()) | value
            let resized = handle.truncate(4) | value
            if value(handle.stat()).size != 4: return panic("handle stat")

            let sought = handle.seek(offset: 0, origin: 0) | value
            if (handle.reader() | read_all | value) != "aXYd".to_bytes(): return panic(
                "reader adapter"
            )

        let closed: Result[Bytes, FileSystemError] = error(FileSystemError.Closed)
        if handle.read_at(offset: 0, max_bytes: 1) != closed: return panic(
            "closed handle"
        )

        handle.close()

test "empty paths are rejected instead of resolving to the working directory":
    let fs = filesystem()
    let invalid: Result[Unit, FileSystemError] = error(
        cause: FileSystemError.InvalidInput
    )
    if fs.remove(path: "", recursive: true) != invalid: return panic(
        "recursive remove of empty path"
    )
    if fs.create_directory(path: "", recursive: true) != invalid: return panic(
        "create empty directory"
    )
    if fs.write_file(path: "", data: "x".to_bytes(), replace: true) != invalid: return panic(
        "write empty path"
    )

    let empty = fs.stat(path: "", follow_links: true)
    if empty.is_ok(): return panic("stat empty path")
    if empty.unwrap_error() != FileSystemError.InvalidInput: return panic(
        "stat empty path error"
    )
