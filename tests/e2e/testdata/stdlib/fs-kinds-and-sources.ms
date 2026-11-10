import (
    expect_equal, expect_error, expect_ok from "@std/test/test.ms",
    DirectoryEntry,
    FileKind,
    OpenMode,
    Seek,
    append_file,
    create_directory,
    open,
    open_directory,
    read_file,
    stat,
    temporary,
    write_atomic,
    write_file from "@std/os/fs.ms",
    ReadStream from "@std/io/io.ms",
    collect from "@std/io/streams.ms",
)

test "whole-file writes take text or bytes and complete through promises":
    let dir = temporary("manuscript-writable-") | try expect_ok
    let root = dir.path()
    write_file("{root}/a.txt", "hello").wait() | try expect_ok
    append_file("{root}/a.txt", " world".to_bytes()).wait() | try expect_ok
    write_atomic("{root}/b.txt", "x").wait() | try expect_ok

    let data = read_file("{root}/a.txt").wait() | try expect_ok
    data.decode_utf8().get("") | try expect_equal("hello world")

test "stat reports one closed kind and follows links by default":
    let dir = temporary("manuscript-kinds-") | try expect_ok
    let root = dir.path()
    write_file("{root}/a.txt", "abc").wait() | try expect_ok
    create_directory("{root}/sub", recursive: false) | try expect_ok

    let file = stat("{root}/a.txt") | try expect_ok
    file.kind | try expect_equal(FileKind.File)
    file.is_file() | try expect_equal(true)
    file.size | try expect_equal(3)

    let sub = stat("{root}/sub") | try expect_ok
    sub.kind | try expect_equal(FileKind.Directory)
    sub.is_directory() | try expect_equal(true)

test "a directory is a stream source of entries and seek takes an origin":
    let dir = temporary("manuscript-source-") | try expect_ok
    let root = dir.path()
    write_file("{root}/a.txt", "hello world").wait() | try expect_ok
    write_file("{root}/b.txt", "").wait() | try expect_ok

    let handle = open("{root}/a.txt", OpenMode.Read) | try expect_ok
    (try handle.seek(6, Seek.Start)) | try expect_equal(6)
    (try handle.seek(-1, Seek.End)) | try expect_equal(10)

    let entries = open_directory(root) | try expect_ok
    let all = ReadStream[DirectoryEntry](entries) | collect(none) | try expect_ok
    all.length() | try expect_equal(2)

test "opening a directory classifies invalid and missing paths":
    let dir = temporary("manuscript-directory-errors-") | try expect_ok
    let root = dir.path()
    let file = "{root}/file.txt"
    write_file(file, "hello").wait() | try expect_ok

    let invalid = open_directory(file) | try expect_error
    invalid.kind | try expect_equal("EINVAL")
    invalid.message.contains(file) | try expect_equal(true)

    let missing = open_directory("{root}/missing") | try expect_error
    missing.kind | try expect_equal("ENOENT")

    let child = "{file}/child"
    let nested = open_directory(child) | try expect_error
    let host_error = stat(child) | try expect_error
    nested.kind | try expect_equal(host_error.kind)

    let valid = open_directory(root) | try expect_ok
    valid.path() | try expect_equal(root)
