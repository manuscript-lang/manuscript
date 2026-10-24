# conform: tags=aliasing,faults,formatter,generics,interpolation,lists,match,modules,parser,stdlib-bytes,stdlib-errors,stdlib-fs,stdlib-testing,strings,testing,tier-io,try-result,with-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/fs-defaults.ms
from "@std/testing.ms" import expect_equal, expect_false, expect_ok, expect_true
from "@std/core.ms" import TextError
from "@std/fs.ms" import filesystem, FileSystem, FileSystemError
from "@std/bytes.ms" import Bytes

def generic_write[T: FileSystem](
    fs: T,
    path: String,
    data: String
) -> Result[Unit, FileSystemError]:
    return fs.write_file(path, data)

def generic_copy[T: FileSystem](
    fs: T,
    source: String,
    destination: String
) -> Result[Unit, FileSystemError]:
    return fs.copy_file(source, destination)

def generic_tree[T: FileSystem](
    fs: T,
    source: String,
    destination: String
) -> Result[Unit, FileSystemError]:
    return fs.copy_tree(source, destination)

def generic_directory[T: FileSystem](
    fs: T,
    path: String
) -> Result[Unit, FileSystemError]:
    return fs.create_directory(path)

def generic_remove[T: FileSystem](fs: T, path: String) -> Result[Unit, FileSystemError]:
    return fs.remove(path)

def rejected(result: Result[Unit, FileSystemError]) -> Result[Unit, Error]:
    match result:
        case error(_): return ok(())
        case ok(_): return error(
            TextError("exclusive or nonrecursive operation succeeded")
        )

    return ok(())

def text(fs: FileSystem, path: String) -> Result[String, Error]:
    return ok((fs.read_file(path) | try expect_ok).decode_utf8().get())

def argument(var log: List[String], mark: String, path: String) -> String:
    log.append(mark)
    return path

def data_argument(var log: List[String]) -> Bytes:
    log.append("data")
    return "new".to_bytes()

test "filesystem writes default to exclusive creation through aliases and bounds":
    let fs = filesystem()

    with (fs.temporary("manuscript-default-write-") | try expect_ok) as temporary:
        let path = f"{temporary.path()}/file"
        (fs.write_file(path, "first") | try expect_ok)

        let write = fs.write_file
        let alias = write
        (try rejected(alias(path, "second")))
        (try rejected(write(path, "second", replace: False)))
        (try rejected(generic_write(fs, path, "second")))
        (try text(fs, path)) | try expect_equal("first")
        (alias(path, "second", replace: True) | try expect_ok)
        (try text(fs, path)) | try expect_equal("second")
        (generic_write(fs, f"{temporary.path()}/generic", "generic") | try expect_ok)
        (try rejected(fs.write_file("", "invalid")))

test "filesystem file copies default to no replacement and retain byte limits":
    let fs: FileSystem = filesystem()

    with (fs.temporary("manuscript-default-copy-") | try expect_ok) as temporary:
        let source = f"{temporary.path()}/source"
        let destination = f"{temporary.path()}/destination"
        (fs.write_file(source, "source") | try expect_ok)

        let copy = fs.copy_file
        let alias = copy
        (alias(source, destination) | try expect_ok)
        (fs.write_file(source, "changed", True) | try expect_ok)
        (try rejected(copy(source, destination)))
        (try rejected(fs.copy_file(source, destination, replace: False)))
        (try rejected(generic_copy(fs, source, destination)))
        (try text(fs, destination)) | try expect_equal("source")
        (copy(source, destination, replace: True, max_bytes: none) | try expect_ok)
        (try text(fs, destination)) | try expect_equal("changed")
        (generic_copy(fs, source, f"{temporary.path()}/generic") | try expect_ok)

        let limited: Result[Unit, FileSystemError] = error(
            FileSystemError.LimitExceeded
        )
        fs.copy_file(source, f"{temporary.path()}/limited", max_bytes: 0) | try expect_equal(
            limited
        )
        fs.copy_file(source, f"{temporary.path()}/limited", max_bytes: 6) | try expect_equal(
            limited
        )

        let invalid: Result[Unit, FileSystemError] = error(FileSystemError.InvalidInput)
        (
            (
                fs.copy_file(
                    source, f"{temporary.path()}/negative", max_bytes: -1
                ) != invalid
            )
        ) | try expect_false
        (copy(source, f"{temporary.path()}/exact", max_bytes: 7) | try expect_ok)

test "filesystem tree copies default to no replacement with distinct budgets":
    let fs = filesystem()

    with (fs.temporary("manuscript-default-tree-") | try expect_ok) as temporary:
        let source = f"{temporary.path()}/source"
        let destination = f"{temporary.path()}/destination"
        (fs.create_directory(source) | try expect_ok)
        (fs.write_file(f"{source}/data", "abc") | try expect_ok)

        let copy = fs.copy_tree
        let alias = copy
        (alias(source, destination) | try expect_ok)
        (fs.write_file(f"{source}/data", "xyz", True) | try expect_ok)
        (try rejected(copy(source, destination)))
        (try rejected(copy(source, destination, False)))
        (try rejected(generic_tree(fs, source, destination)))
        (try text(fs, f"{destination}/data")) | try expect_equal("abc")
        (
            copy(
                source, destination, True, max_entries: none, max_bytes: none
            ) | try expect_ok
        )
        (try text(fs, f"{destination}/data")) | try expect_equal("xyz")
        (generic_tree(fs, source, f"{temporary.path()}/generic") | try expect_ok)

        let limited: Result[Unit, FileSystemError] = error(
            FileSystemError.LimitExceeded
        )
        copy(source, f"{temporary.path()}/entries", max_entries: 1) | try expect_equal(
            limited
        )
        copy(source, f"{temporary.path()}/bytes", max_bytes: 2) | try expect_equal(
            limited
        )

        let invalid: Result[Unit, FileSystemError] = error(FileSystemError.InvalidInput)
        (
            (
                copy(
                    source, f"{temporary.path()}/negative-entry", max_entries: -1
                ) != invalid
            )
        ) | try expect_false
        copy(source, f"{temporary.path()}/negative-byte", max_bytes: -1) | try expect_equal(
            invalid
        )
        (
            copy(
                source, f"{temporary.path()}/exact", max_entries: 2, max_bytes: 3
            ) | try expect_ok
        )

test "filesystem directory creation defaults to requiring an existing parent":
    let fs = filesystem()

    with (fs.temporary("manuscript-default-directory-") | try expect_ok) as temporary:
        let create = fs.create_directory
        let alias = create
        let child = f"{temporary.path()}/missing/child"
        (try rejected(alias(child)))
        (try rejected(create(child, False)))
        (try rejected(generic_directory(fs, child)))
        (fs.list(temporary.path()) | try expect_ok).length() | try expect_equal(0)
        (create(child, recursive: True) | try expect_ok)
        ((fs.stat(child, follow_links: False) | try expect_ok).directory) | try expect_true
        (generic_directory(fs, f"{temporary.path()}/generic") | try expect_ok)
        (try rejected(create("")))

test "filesystem removal defaults to retaining nonempty trees":
    let fs = filesystem()

    with (fs.temporary("manuscript-default-remove-") | try expect_ok) as temporary:
        let directory = f"{temporary.path()}/nonempty"
        let path = f"{directory}/keep"
        (fs.create_directory(directory) | try expect_ok)
        (fs.write_file(path, "keep") | try expect_ok)

        let remove = fs.remove
        let alias = remove
        (try rejected(alias(directory)))
        (try rejected(remove(directory, False)))
        (try rejected(generic_remove(fs, directory)))
        (try text(fs, path)) | try expect_equal("keep")
        (remove(directory, recursive: True) | try expect_ok)

        let empty = f"{temporary.path()}/empty"
        (fs.create_directory(empty) | try expect_ok)
        (alias(empty) | try expect_ok)
        (fs.write_file(f"{temporary.path()}/file", "file") | try expect_ok)
        (generic_remove(fs, f"{temporary.path()}/file") | try expect_ok)
        (try rejected(remove("")))

test "filesystem default preparation retains written argument order":
    let fs = filesystem()

    with (fs.temporary("manuscript-default-order-") | try expect_ok) as temporary:
        var log: List[String] = []
        (
            fs.write_file_bytes(
                data: data_argument(var log),
                path: argument(
                    var log, "path", f"{temporary.path()}/ordered"
                )
            ) | try expect_ok
        )
        log | try expect_equal(["data", "path"])

        let copy = fs.copy_file
        (
            copy(
                destination: argument(
                    var log, "destination", f"{temporary.path()}/copy"
                ),
                source: argument(
                    var log, "source", f"{temporary.path()}/ordered"
                )
            ) | try expect_ok
        )
        log | try expect_equal(["data", "path", "destination", "source"])
