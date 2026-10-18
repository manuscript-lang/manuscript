import {filesystem, FileSystemError, GlobOptions, PathEntry} from "@std/fs.ms"
import {files, read_all} from "@std/io.ms"
import Bytes from "@std/bytes.ms"
import panic from "@std/faults.ms"
import expect_error from "@std/testing.ms"

fn expect_fs_error[T](
    outcome: Result[T, FileSystemError],
    expected: FileSystemError
) Unit:
    if not outcome.is_error(): return panic("filesystem misuse succeeded")
    if outcome.unwrap_error() != expected: return panic("wrong filesystem error")

test "glob queries reuse patterns without changing hidden paths limits or callbacks":
    let fs = filesystem()

    with temporary = try fs.temporary("manuscript-glob-"):
        let root = temporary.path()
        try fs.create_directory(path: "{root}/sub", recursive: false)
        for name in ["a.txt", "b.md", ".hidden.txt", "sub/c.txt"]:
            try fs.write_file(
                path: "{root}/{name}",
                data: "".to_bytes(),
                replace: false
            )
        let matches = try fs.glob(path: root, pattern: "**/*.\{txt,md\}")
        if matches != ["a.txt", "b.md", "sub/c.txt"]: return panic("glob matches")

        expect_fs_error(
            fs.glob(path: root, pattern: "**/*.\{txt,md\}", max_entries: 2),
            FileSystemError.LimitExceeded
        )
        expect_fs_error(
            fs.glob(path: root, pattern: "\{a.txt,[\}"),
            FileSystemError.InvalidInput
        )
        let options = GlobOptions(
            patterns: ["*.txt"],
            exclude: ["sub/**"],
            follow_links: false
        )
        let entries = try fs.glob_entries(
            path: root,
            options: options,
            exclude: some(
                fn(entry: PathEntry) Bool:
                    if entry.path == ".": options.patterns.set(0, "*.md")
                    return false
            )
        )
        if entries.length() != 1: return panic("glob_entries count")
        if entries.at(0).unwrap().path != "b.md": return panic(
            "callback changed pattern"
        )

test "ordinary filesystem misuse retains typed cases":
    let fs = filesystem()

    with temporary = try fs.temporary("manuscript-errors-"):
        let directory = "{temporary.path()}/directory"
        let file = "{temporary.path()}/file"
        try fs.create_directory(path: directory, recursive: false)
        try fs.write_file(
            path: "{directory}/child",
            data: "x".to_bytes(),
            replace: false
        )
        try fs.write_file(path: file, data: "abc".to_bytes(), replace: false)
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

        with reader = try fs.open(path: file, flags: "r", mode: 384):
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

        with writer = try fs.open(path: file, flags: "a", mode: 384):
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

    with temporary = try fs.temporary("manuscript-stdlib-"):
        directory = temporary.path()
        let path = "{directory}/data.txt"
        try fs.write_file(path: path, data: "hello".to_bytes(), replace: false)
        if ((try fs.read_file(path: path, max_bytes: 5)) != "hello".to_bytes()): return panic(
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
        if (try fs.stat(path: path, follow_links: true)).size != 5: return panic(
            "file stat"
        )
        if (try fs.list(path: directory)).length() != 1: return panic("directory list")

        with input = try files().open(path):
            if (try input.read(5)).unwrap() != "hello".to_bytes(): return panic(
                "read-only Files host"
            )

    if (
        (
            try expect_error(fs.stat(path: directory, follow_links: true))
        ) != FileSystemError.NotFound
    ): return panic("temporary cleanup error")

test "file handles positional I/O stream adapters and closed errors":
    let fs = filesystem()

    with temporary = try fs.temporary("manuscript-handles-"):
        let path = "{temporary.path()}/data.txt"
        try fs.write_file(path: path, data: "abcdef".to_bytes(), replace: false)
        let handle = try fs.open(path: path, flags: "r+", mode: 384)

        with scoped = handle:
            if ((try handle.read_at(offset: 2, max_bytes: 2)) != "cd".to_bytes()): return panic(
                "positional read"
            )

            try handle.write_at(offset: 1, data: "XY".to_bytes())
            try handle.truncate(4)
            if (try handle.stat()).size != 4: return panic("handle stat")

            let _count = try handle.seek(offset: 0, origin: 0)
            if (try read_all(input: handle.reader())) != "aXYd".to_bytes(): return panic(
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
    if (
        (
            try expect_error(fs.stat(path: "", follow_links: true))
        ) != FileSystemError.InvalidInput
    ): return panic("stat empty path error")
