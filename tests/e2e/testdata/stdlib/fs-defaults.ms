import expect_equal, expect_error, expect_ok, expect_true from "@std/test/test.ms"
import (
    copy,
    CopyOptions,
    create_directory,
    list,
    read_file,
    remove,
    stat,
    temporary,
    write_file
) from "@std/os/fs.ms"
import Bytes from "@std/bytes.ms"

fn expect_limit(outcome: Unit!) Unit!:
    cause := try expect_error(outcome)
    try expect_equal(cause.kind, "EOVERFLOW")
    if not cause.message.starts_with("filesystem: limit exceeded"):
        return error(Error("wrong limit message: {cause.message}"))

    return ok(unit)

fn generic_write(path: String, data: String) Unit!:
    return write_file(path, data).wait()

fn generic_copy(source: String, destination: String) Unit!:
    return copy(source, destination)

fn generic_tree(source: String, destination: String) Unit!:
    return copy(source, destination, CopyOptions(recursive: true))

fn generic_directory(path: String) Unit!:
    return create_directory(path)

fn generic_remove(path: String) Unit!:
    return remove(path)

fn rejected(result: Unit!) Unit!:
    match result:
        error(_): return ok(unit)
        ok(_): return error(Error("exclusive or nonrecursive operation succeeded"))

    return ok(unit)

fn text(path: String) String!:
    return ok((read_file(path).wait() | try expect_ok).decode_utf8().get())

fn argument(var log: List[String], mark: String, path: String) String:
    log.append(mark)
    return path

fn data_argument(var log: List[String]) Bytes:
    log.append("data")
    return "new".to_bytes()

test "filesystem writes default to exclusive creation through aliases and bounds":
    temporary := temporary("manuscript-default-write-") | try expect_ok
    path := "{temporary.path()}/file"
    write_file(path, "first").wait() | try expect_ok

    write := write_file
    alias := write_file
    (try rejected(alias(path, "second").wait()))
    (try rejected(write(path, "second", replace: false).wait()))
    (try rejected(generic_write(path, "second")))
    (try text(path)) | try expect_equal("first")
    (alias(path, "second", replace: true).wait() | try expect_ok)
    (try text(path)) | try expect_equal("second")
    (generic_write("{temporary.path()}/generic", "generic") | try expect_ok)
    (try rejected(write_file("", "invalid").wait()))

test "filesystem file copies default to no replacement and retain byte limits":
    temporary := temporary("manuscript-default-copy-") | try expect_ok
    source := "{temporary.path()}/source"
    destination := "{temporary.path()}/destination"
    write_file(source, "source").wait() | try expect_ok

    alias := copy
    (alias(source, destination) | try expect_ok)
    write_file(source, "changed", true).wait() | try expect_ok
    (try rejected(copy(source, destination)))
    (try rejected(copy(source, destination, CopyOptions(replace: false))))
    (try rejected(generic_copy(source, destination)))
    (try text(destination)) | try expect_equal("source")
    (copy(source, destination, CopyOptions(replace: true)) | try expect_ok)
    (try text(destination)) | try expect_equal("changed")
    (generic_copy(source, "{temporary.path()}/generic") | try expect_ok)
    copy(source, "{temporary.path()}/limited", CopyOptions(max_bytes: 0)) | try expect_limit
    copy(source, "{temporary.path()}/limited", CopyOptions(max_bytes: 6)) | try expect_limit
    (
        copy(
            source, "{temporary.path()}/exact", CopyOptions(max_bytes: 7)
        ) | try expect_ok
    )

test "filesystem tree copies default to no replacement with distinct budgets":
    temporary := temporary("manuscript-default-tree-") | try expect_ok
    source := "{temporary.path()}/source"
    destination := "{temporary.path()}/destination"
    tree := CopyOptions(recursive: true)
    create_directory(source) | try expect_ok
    write_file("{source}/data", "abc").wait() | try expect_ok

    alias := copy
    (alias(source, destination, tree) | try expect_ok)
    write_file("{source}/data", "xyz", true).wait() | try expect_ok
    (try rejected(copy(source, destination, tree)))
    (
        try rejected(
            copy(
                source, destination, CopyOptions(recursive: true, replace: false)
            )
        )
    )
    (try rejected(generic_tree(source, destination)))
    (try text("{destination}/data")) | try expect_equal("abc")
    (
        copy(
            source, destination, CopyOptions(recursive: true, replace: true)
        ) | try expect_ok
    )
    (try text("{destination}/data")) | try expect_equal("xyz")
    (generic_tree(source, "{temporary.path()}/generic") | try expect_ok)
    copy(
        source, "{temporary.path()}/entries",
        CopyOptions(recursive: true, max_entries: 1)
    ) | try expect_limit
    copy(source, "{temporary.path()}/bytes", CopyOptions(recursive: true, max_bytes: 2)) | try expect_limit

    invalid: Unit! = error(Error("filesystem: invalid input", kind: "EINVAL"))
    copy(
        source, "{temporary.path()}/negative-byte",
        CopyOptions(recursive: true, max_bytes: -1)
    ) | try expect_equal(invalid)
    (
        copy(
            source, "{temporary.path()}/exact",
            CopyOptions(recursive: true, max_entries: 2, max_bytes: 3)
        ) | try expect_ok
    )

test "filesystem directory creation defaults to requiring an existing parent":
    temporary := temporary("manuscript-default-directory-") | try expect_ok
    create := create_directory
    alias := create_directory
    child := "{temporary.path()}/missing/child"
    (try rejected(alias(child)))
    (try rejected(create(child, false)))
    (try rejected(generic_directory(child)))
    (list(temporary.path()) | try expect_ok).length() | try expect_equal(0)
    (create(child, recursive: true) | try expect_ok)
    ((stat(child, follow_links: false) | try expect_ok).is_directory()) | try expect_true
    (generic_directory("{temporary.path()}/generic") | try expect_ok)
    (try rejected(create("")))

test "filesystem removal defaults to retaining nonempty trees":
    temporary := temporary("manuscript-default-remove-") | try expect_ok
    directory := "{temporary.path()}/nonempty"
    path := "{directory}/keep"
    create_directory(directory) | try expect_ok
    write_file(path, "keep").wait() | try expect_ok

    eraser := remove
    alias := remove
    (try rejected(alias(directory)))
    (try rejected(eraser(directory, false)))
    (try rejected(generic_remove(directory)))
    (try text(path)) | try expect_equal("keep")
    (remove(directory, recursive: true) | try expect_ok)

    empty := "{temporary.path()}/empty"
    create_directory(empty) | try expect_ok
    (alias(empty) | try expect_ok)
    write_file("{temporary.path()}/file", "file").wait() | try expect_ok
    (generic_remove("{temporary.path()}/file") | try expect_ok)
    (try rejected(eraser("")))

test "filesystem default preparation retains written argument order":
    temporary := temporary("manuscript-default-order-") | try expect_ok
    var log: List[String] = []
    write_file(
        data: data_argument(var log),
        path: argument(var log, "path", "{temporary.path()}/ordered")
    ).wait() | try expect_ok
    log | try expect_equal(["data", "path"])

    copy := copy
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
