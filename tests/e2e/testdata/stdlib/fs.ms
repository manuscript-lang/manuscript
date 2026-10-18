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
    if outcome.err() != expected: return panic("wrong filesystem error")

test "glob queries reuse patterns without changing hidden paths limits or callbacks":
    let fs = filesystem()

    with temporary = try fs.temporary("manuscript-glob-"):
        let root = temporary.path()
        try fs.create_directory("{root}/sub", recursive: false)
        for name in ["a.txt", "b.md", ".hidden.txt", "sub/c.txt"]:
            try fs.write_file("{root}/{name}", "", replace: false)
        let matches = try fs.glob(root, "**/*.\{txt,md\}")
        if matches != ["a.txt", "b.md", "sub/c.txt"]: return panic("glob matches")

        expect_fs_error(
            fs.glob(root, "**/*.\{txt,md\}", 2),
            FileSystemError.LimitExceeded
        )
        expect_fs_error(fs.glob(root, "\{a.txt,[\}"), FileSystemError.InvalidInput)
        let options = GlobOptions(["*.txt"], ["sub/**"], follow_links: false)
        let entries = try fs.glob_entries(
            root,
            options,
            some(
                fn(entry: PathEntry) Bool:
                    if entry.path == ".": options.patterns.set(0, "*.md")
                    return false
            )
        )
        if entries.length() != 1: return panic("glob_entries count")
        if entries.at(0).get().path != "b.md": return panic("callback changed pattern")

test "ordinary filesystem misuse retains typed cases":
    let fs = filesystem()

    with temporary = try fs.temporary("manuscript-errors-"):
        let directory = "{temporary.path()}/directory"
        let file = "{temporary.path()}/file"
        try fs.create_directory(directory, recursive: false)
        try fs.write_file("{directory}/child", "x", replace: false)
        try fs.write_file(file, "abc", replace: false)
        expect_fs_error(
            fs.remove(directory, recursive: false),
            FileSystemError.NotEmpty
        )
        expect_fs_error(fs.list(file), FileSystemError.InvalidInput)
        expect_fs_error(fs.read_file(directory), FileSystemError.InvalidInput)
        expect_fs_error(
            fs.create_directory(file, recursive: false),
            FileSystemError.AlreadyExists
        )

        with reader = try fs.open(file, "r", 384):
            expect_fs_error(reader.write("x"), FileSystemError.InvalidInput)
            expect_fs_error(reader.seek(-1, 0), FileSystemError.InvalidInput)
            expect_fs_error(reader.seek(0, 3), FileSystemError.InvalidInput)

        with writer = try fs.open(file, "a", 384):
            expect_fs_error(writer.read(1), FileSystemError.InvalidInput)
            expect_fs_error(writer.read_file(), FileSystemError.InvalidInput)

test "filesystem scoped temporary directories and bounded file reads":
    let fs = filesystem()
    var directory = ""

    with temporary = try fs.temporary("manuscript-stdlib-"):
        directory = temporary.path()
        let path = "{directory}/data.txt"
        try fs.write_file(path, "hello", replace: false)
        if ((try fs.read_file(path, 5)) != "hello".to_bytes()): return panic(
            "read file"
        )

        let limited: Result[Bytes, FileSystemError] = error(
            FileSystemError.LimitExceeded
        )
        if fs.read_file(path, 4) != limited: return panic("file byte limit")

        let exists: Result[Unit, FileSystemError] = error(FileSystemError.AlreadyExists)
        if (fs.write_file(path, "changed", replace: false) != exists): return panic(
            "exclusive write"
        )
        if (try fs.stat(path, follow_links: true)).size != 5: return panic("file stat")
        if (try fs.list(directory)).length() != 1: return panic("directory list")

        with input = try files().open(path):
            if (try input.read(5)).get() != "hello".to_bytes(): return panic(
                "read-only Files host"
            )

    if (
        (
            try expect_error(fs.stat(directory, follow_links: true))
        ) != FileSystemError.NotFound
    ): return panic("temporary cleanup error")

test "file handles positional I/O stream adapters and closed errors":
    let fs = filesystem()

    with temporary = try fs.temporary("manuscript-handles-"):
        let path = "{temporary.path()}/data.txt"
        try fs.write_file(path, "abcdef", replace: false)
        let handle = try fs.open(path, "r+", 384)

        with scoped = handle:
            if ((try handle.read_at(2, 2)) != "cd".to_bytes()): return panic(
                "positional read"
            )

            try handle.write_at(1, "XY")
            try handle.truncate(4)
            if (try handle.stat()).size != 4: return panic("handle stat")

            let _count = try handle.seek(0, 0)
            if (try read_all(handle.reader())) != "aXYd".to_bytes(): return panic(
                "reader adapter"
            )

        let closed: Result[Bytes, FileSystemError] = error(FileSystemError.Closed)
        if handle.read_at(0, 1) != closed: return panic("closed handle")

        handle.close()

test "empty paths are rejected instead of resolving to the working directory":
    let fs = filesystem()
    let invalid: Result[Unit, FileSystemError] = error(
        cause: FileSystemError.InvalidInput
    )
    if fs.remove("", recursive: true) != invalid: return panic(
        "recursive remove of empty path"
    )
    if fs.create_directory("", recursive: true) != invalid: return panic(
        "create empty directory"
    )
    if fs.write_file("", "x", replace: true) != invalid: return panic(
        "write empty path"
    )
    if (
        (
            try expect_error(fs.stat("", follow_links: true))
        ) != FileSystemError.InvalidInput
    ): return panic("stat empty path error")
