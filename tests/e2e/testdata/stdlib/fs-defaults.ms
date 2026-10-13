import {filesystem, FileSystem, FileSystemError} from "@std/fs.ms"
import Bytes from "@std/bytes.ms"
import List from "@std/collections.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

fn generic_write[T: FileSystem](
    fs: T,
    path: String,
    data: Bytes
) -> Result[Unit, FileSystemError]:
    return fs.write_file(path, data)

fn generic_copy[T: FileSystem](
    fs: T,
    source: String,
    destination: String
) -> Result[Unit, FileSystemError]:
    return fs.copy_file(source, destination)

fn generic_tree[T: FileSystem](
    fs: T,
    source: String,
    destination: String
) -> Result[Unit, FileSystemError]:
    return fs.copy_tree(source, destination)

fn generic_directory[T: FileSystem](
    fs: T,
    path: String
) -> Result[Unit, FileSystemError]:
    return fs.create_directory(path)

fn generic_remove[T: FileSystem](fs: T, path: String) -> Result[Unit, FileSystemError]:
    return fs.remove(path)

fn rejected(result: Result[Unit, FileSystemError]) -> Unit:
    match result:
        error(_): return
        ok(_): return panic("exclusive or nonrecursive operation succeeded")

fn text(fs: FileSystem, path: String) -> String:
    return value(fs.read_file(path)).to_text().unwrap()

fn argument(log: List[String], mark: String, path: String) -> String:
    log.append(mark)
    return path

fn data_argument(log: List[String]) -> Bytes:
    log.append("data")
    return "new".to_bytes()

test "filesystem writes default to exclusive creation through aliases and bounds":
    let fs = filesystem()

    with temporary = value(fs.temporary("manuscript-default-write-")):
        let path = "{temporary.path()}/file"
        value(
            fs.write_file(
                path,
                "first".to_bytes()
            )
        )
        let write = fs.write_file
        let alias = write
        rejected(
            alias(
                path,
                "second".to_bytes()
            )
        )
        rejected(
            write(
                path,
                "second".to_bytes(),
                replace: false
            )
        )
        rejected(
            generic_write(
                fs,
                path,
                "second".to_bytes()
            )
        )
        if text(fs, path) != "first": return panic("omission replaced existing data")

        value(
            alias(
                path,
                "second".to_bytes(),
                replace: true
            )
        )
        if text(fs, path) != "second": return panic("explicit replacement lost")

        value(
            generic_write(
                fs,
                "{temporary.path()}/generic",
                "generic".to_bytes()
            )
        )
        rejected(
            fs.write_file(
                "",
                "invalid".to_bytes()
            )
        )

test "filesystem file copies default to no replacement and retain byte limits":
    let fs: FileSystem = filesystem()

    with temporary = value(fs.temporary("manuscript-default-copy-")):
        let source = "{temporary.path()}/source"
        let destination = "{temporary.path()}/destination"
        value(
            fs.write_file(
                source,
                "source".to_bytes()
            )
        )
        let copy = fs.copy_file
        let alias = copy
        value(alias(source, destination))
        value(
            fs.write_file(
                source,
                "changed".to_bytes(),
                true
            )
        )
        rejected(copy(source, destination))
        rejected(fs.copy_file(source, destination, replace: false))
        rejected(generic_copy(fs, source, destination))
        if text(fs, destination) != "source": return panic("copy overwrote destination")

        value(
            copy(
                source,
                destination,
                replace: true,
                max_bytes: none
            )
        )
        if text(fs, destination) != "changed": return panic("explicit copy replacement")

        value(generic_copy(fs, source, "{temporary.path()}/generic"))
        let limited: Result[Unit, FileSystemError] = error(
            FileSystemError.LimitExceeded
        )
        if fs.copy_file(source, "{temporary.path()}/limited", max_bytes: 0) != limited: return panic(
            "zero byte limit"
        )
        if fs.copy_file(source, "{temporary.path()}/limited", max_bytes: 6) != limited: return panic(
            "copy byte limit"
        )

        let invalid: Result[Unit, FileSystemError] = error(FileSystemError.InvalidInput)
        if (
            fs.copy_file(
                source,
                "{temporary.path()}/negative",
                max_bytes: -1
            ) != invalid
        ): return panic("negative byte limit")

        value(copy(source, "{temporary.path()}/exact", max_bytes: 7))

test "filesystem tree copies default to no replacement with distinct budgets":
    let fs = filesystem()

    with temporary = value(fs.temporary("manuscript-default-tree-")):
        let source = "{temporary.path()}/source"
        let destination = "{temporary.path()}/destination"
        value(fs.create_directory(source))
        value(
            fs.write_file(
                "{source}/data",
                "abc".to_bytes()
            )
        )
        let copy = fs.copy_tree
        let alias = copy
        value(alias(source, destination))
        value(
            fs.write_file(
                "{source}/data",
                "xyz".to_bytes(),
                true
            )
        )
        rejected(copy(source, destination))
        rejected(copy(source, destination, false))
        rejected(generic_tree(fs, source, destination))
        if text(fs, "{destination}/data") != "abc": return panic(
            "tree replaced existing data"
        )

        value(
            copy(
                source,
                destination,
                true,
                max_entries: none,
                max_bytes: none
            )
        )
        if text(fs, "{destination}/data") != "xyz": return panic(
            "explicit tree replacement"
        )

        value(generic_tree(fs, source, "{temporary.path()}/generic"))
        let limited: Result[Unit, FileSystemError] = error(
            FileSystemError.LimitExceeded
        )
        if copy(source, "{temporary.path()}/entries", max_entries: 1) != limited: return panic(
            "entry budget"
        )
        if copy(source, "{temporary.path()}/bytes", max_bytes: 2) != limited: return panic(
            "byte budget"
        )

        let invalid: Result[Unit, FileSystemError] = error(FileSystemError.InvalidInput)
        if (
            copy(
                source,
                "{temporary.path()}/negative-entry",
                max_entries: -1
            ) != invalid
        ): return panic("negative entries")
        if copy(source, "{temporary.path()}/negative-byte", max_bytes: -1) != invalid: return panic(
            "negative bytes"
        )

        value(
            copy(
                source,
                "{temporary.path()}/exact",
                max_entries: 2,
                max_bytes: 3
            )
        )

test "filesystem directory creation defaults to requiring an existing parent":
    let fs = filesystem()

    with temporary = value(fs.temporary("manuscript-default-directory-")):
        let create = fs.create_directory
        let alias = create
        let child = "{temporary.path()}/missing/child"
        rejected(alias(child))
        rejected(create(child, false))
        rejected(generic_directory(fs, child))
        if value(
            fs.list(temporary.path())
        ).length() != 0: return panic("default created parents")

        value(create(child, recursive: true))
        if not value(fs.stat(child, follow_links: false)).directory: return panic(
            "recursive creation"
        )

        value(generic_directory(fs, "{temporary.path()}/generic"))
        rejected(create(""))

test "filesystem removal defaults to retaining nonempty trees":
    let fs = filesystem()

    with temporary = value(fs.temporary("manuscript-default-remove-")):
        let directory = "{temporary.path()}/nonempty"
        let path = "{directory}/keep"
        value(fs.create_directory(directory))
        value(
            fs.write_file(
                path,
                "keep".to_bytes()
            )
        )
        let remove = fs.remove
        let alias = remove
        rejected(alias(directory))
        rejected(remove(directory, false))
        rejected(generic_remove(fs, directory))
        if text(fs, path) != "keep": return panic("default removed descendants")

        value(remove(directory, recursive: true))
        let empty = "{temporary.path()}/empty"
        value(fs.create_directory(empty))
        value(alias(empty))
        value(
            fs.write_file(
                "{temporary.path()}/file",
                "file".to_bytes()
            )
        )
        value(generic_remove(fs, "{temporary.path()}/file"))
        rejected(remove(""))

test "filesystem default preparation retains written argument order":
    let fs = filesystem()

    with temporary = value(fs.temporary("manuscript-default-order-")):
        let log: List[String] = []
        value(
            fs.write_file(
                data: data_argument(log),
                path: argument(
                    log,
                    "path",
                    "{temporary.path()}/ordered"
                )
            )
        )
        if log != ["data", "path"]: return panic("default reordered supplied arguments")

        let copy = fs.copy_file
        value(
            copy(
                destination: argument(
                    log,
                    "destination",
                    "{temporary.path()}/copy"
                ),
                source: argument(
                    log,
                    "source",
                    "{temporary.path()}/ordered"
                )
            )
        )
        if log != ["data", "path", "destination", "source"]: return panic(
            "bound default reordered arguments"
        )
