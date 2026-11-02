import expect_equal, expect_false, expect_ok, expect_true from "@std/test/test.ms"
import TextError from "@std/core.ms"
import (
    FileSystemError,
    copy_file,
    copy_tree,
    create_directory,
    list,
    read_file,
    remove,
    stat,
    temporary,
    write_file,
    write_file_bytes
) from "@std/os/fs.ms"
import Bytes from "@std/bytes.ms"

fn generic_write(path: String, data: String) Unit!FileSystemError:
    return write_file(path, data)

fn generic_copy(source: String, destination: String) Unit!FileSystemError:
    return copy_file(source, destination)

fn generic_tree(source: String, destination: String) Unit!FileSystemError:
    return copy_tree(source, destination)

fn generic_directory(path: String) Unit!FileSystemError:
    return create_directory(path)

fn generic_remove(path: String) Unit!FileSystemError:
    return remove(path)

fn rejected(result: Unit!FileSystemError) Unit!:
    match result:
        error(_): return ok(unit)
        ok(_): return error(TextError("exclusive or nonrecursive operation succeeded"))

    return ok(unit)

fn text(path: String) String!:
    return ok((read_file(path) | try expect_ok).decode_utf8().get())

fn argument(var log: List[String], mark: String, path: String) String:
    log.append(mark)
    return path

fn data_argument(var log: List[String]) Bytes:
    log.append("data")
    return "new".to_bytes()

test "filesystem writes default to exclusive creation through aliases and bounds":
    let temporary = temporary("manuscript-default-write-") | try expect_ok
    let path = "{temporary.path()}/file"
    write_file(path, "first") | try expect_ok

    let write = write_file
    let alias = write_file
    (try rejected(alias(path, "second")))
    (try rejected(write(path, "second", replace: false)))
    (try rejected(generic_write(path, "second")))
    (try text(path)) | try expect_equal("first")
    (alias(path, "second", replace: true) | try expect_ok)
    (try text(path)) | try expect_equal("second")
    (generic_write("{temporary.path()}/generic", "generic") | try expect_ok)
    (try rejected(write_file("", "invalid")))

test "filesystem file copies default to no replacement and retain byte limits":
    let temporary = temporary("manuscript-default-copy-") | try expect_ok
    let source = "{temporary.path()}/source"
    let destination = "{temporary.path()}/destination"
    write_file(source, "source") | try expect_ok

    let copy = copy_file
    let alias = copy_file
    (alias(source, destination) | try expect_ok)
    write_file(source, "changed", true) | try expect_ok
    (try rejected(copy(source, destination)))
    (try rejected(copy_file(source, destination, replace: false)))
    (try rejected(generic_copy(source, destination)))
    (try text(destination)) | try expect_equal("source")
    (copy(source, destination, replace: true, max_bytes: none) | try expect_ok)
    (try text(destination)) | try expect_equal("changed")
    (generic_copy(source, "{temporary.path()}/generic") | try expect_ok)

    let limited: Unit!FileSystemError = error(FileSystemError.LimitExceeded)
    copy_file(source, "{temporary.path()}/limited", max_bytes: 0) | try expect_equal(
        limited
    )
    copy_file(source, "{temporary.path()}/limited", max_bytes: 6) | try expect_equal(
        limited
    )

    let invalid: Unit!FileSystemError = error(FileSystemError.InvalidInput)
    ((copy_file(source, "{temporary.path()}/negative", max_bytes: -1) != invalid)) | try expect_false
    (copy(source, "{temporary.path()}/exact", max_bytes: 7) | try expect_ok)

test "filesystem tree copies default to no replacement with distinct budgets":
    let temporary = temporary("manuscript-default-tree-") | try expect_ok
    let source = "{temporary.path()}/source"
    let destination = "{temporary.path()}/destination"
    create_directory(source) | try expect_ok
    write_file("{source}/data", "abc") | try expect_ok

    let copy = copy_tree
    let alias = copy_tree
    (alias(source, destination) | try expect_ok)
    write_file("{source}/data", "xyz", true) | try expect_ok
    (try rejected(copy(source, destination)))
    (try rejected(copy(source, destination, false)))
    (try rejected(generic_tree(source, destination)))
    (try text("{destination}/data")) | try expect_equal("abc")
    (
        copy(
            source, destination, true, max_entries: none, max_bytes: none
        ) | try expect_ok
    )
    (try text("{destination}/data")) | try expect_equal("xyz")
    (generic_tree(source, "{temporary.path()}/generic") | try expect_ok)

    let limited: Unit!FileSystemError = error(FileSystemError.LimitExceeded)
    copy(source, "{temporary.path()}/entries", max_entries: 1) | try expect_equal(
        limited
    )
    copy(source, "{temporary.path()}/bytes", max_bytes: 2) | try expect_equal(limited)

    let invalid: Unit!FileSystemError = error(FileSystemError.InvalidInput)
    ((copy(source, "{temporary.path()}/negative-entry", max_entries: -1) != invalid)) | try expect_false
    copy(source, "{temporary.path()}/negative-byte", max_bytes: -1) | try expect_equal(
        invalid
    )
    (
        copy(
            source, "{temporary.path()}/exact", max_entries: 2, max_bytes: 3
        ) | try expect_ok
    )

test "filesystem directory creation defaults to requiring an existing parent":
    let temporary = temporary("manuscript-default-directory-") | try expect_ok
    let create = create_directory
    let alias = create_directory
    let child = "{temporary.path()}/missing/child"
    (try rejected(alias(child)))
    (try rejected(create(child, false)))
    (try rejected(generic_directory(child)))
    (list(temporary.path()) | try expect_ok).length() | try expect_equal(0)
    (create(child, recursive: true) | try expect_ok)
    ((stat(child, follow_links: false) | try expect_ok).directory) | try expect_true
    (generic_directory("{temporary.path()}/generic") | try expect_ok)
    (try rejected(create("")))

test "filesystem removal defaults to retaining nonempty trees":
    let temporary = temporary("manuscript-default-remove-") | try expect_ok
    let directory = "{temporary.path()}/nonempty"
    let path = "{directory}/keep"
    create_directory(directory) | try expect_ok
    write_file(path, "keep") | try expect_ok

    let eraser = remove
    let alias = remove
    (try rejected(alias(directory)))
    (try rejected(eraser(directory, false)))
    (try rejected(generic_remove(directory)))
    (try text(path)) | try expect_equal("keep")
    (remove(directory, recursive: true) | try expect_ok)

    let empty = "{temporary.path()}/empty"
    create_directory(empty) | try expect_ok
    (alias(empty) | try expect_ok)
    write_file("{temporary.path()}/file", "file") | try expect_ok
    (generic_remove("{temporary.path()}/file") | try expect_ok)
    (try rejected(eraser("")))

test "filesystem default preparation retains written argument order":
    let temporary = temporary("manuscript-default-order-") | try expect_ok
    var log: List[String] = []
    write_file_bytes(
        data: data_argument(var log),
        path: argument(var log, "path", "{temporary.path()}/ordered")
    ) | try expect_ok
    log | try expect_equal(["data", "path"])

    let copy = copy_file
    (
        copy(
            destination: argument(
                var log, "destination", "{temporary.path()}/copy"
            ),
            source: argument(
                var log, "source", "{temporary.path()}/ordered"
            )
        ) | try expect_ok
    )
    log | try expect_equal(["data", "path", "destination", "source"])
