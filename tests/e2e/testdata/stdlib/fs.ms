import {filesystem, FileSystemError, FileHandle} from "@std/fs.ms"
import {files, read_all, IoError} from "@std/io.ms"
import {List, Map} from "@std/collections.ms"
import Bytes from "@std/bytes.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "filesystem scoped temporary directories and bounded file reads":
    let fs = filesystem()
    var directory = ""
    with temporary = value(fs.temporary("manuscript-stdlib-")):
        directory = temporary.path()
        let path = "{directory}/data.txt"
        let written = value(fs.write_file(path: path, data: "hello".to_bytes(), replace: false))
        if value(fs.read_file(path: path, max_bytes: some(value: 5))) != "hello".to_bytes(): return panic("read file")
        let limited: Result[Bytes, FileSystemError] = error(cause: FileSystemError.LimitExceeded)
        if fs.read_file(path: path, max_bytes: some(value: 4)) != limited: return panic("file byte limit")
        let exists: Result[Unit, FileSystemError] = error(cause: FileSystemError.AlreadyExists)
        if fs.write_file(path: path, data: "changed".to_bytes(), replace: false) != exists: return panic("exclusive write")
        if value(fs.stat(path: path, follow_links: true)).size != 5: return panic("file stat")
        if value(fs.list(path: directory)).length() != 1: return panic("directory list")
        with input = value(files().open(path)):
            if value(input.read(some(value: 5))).unwrap() != "hello".to_bytes(): return panic("read-only Files host")
    match fs.stat(path: directory, follow_links: true):
        ok(_): return panic("temporary directory not removed")
        error(cause):
            if cause != FileSystemError.NotFound: return panic("temporary cleanup error")

test "file handles positional I/O stream adapters and closed errors":
    let fs = filesystem()
    with temporary = value(fs.temporary("manuscript-handles-")):
        let path = "{temporary.path()}/data.txt"
        let written = value(fs.write_file(path: path, data: "abcdef".to_bytes(), replace: false))
        let handle = value(fs.open(path: path, flags: "r+", mode: 384))
        with scoped = handle:
            if value(handle.read_at(offset: 2, max_bytes: some(value: 2))) != "cd".to_bytes(): return panic("positional read")
            if value(handle.write_at(offset: 1, data: "XY".to_bytes())) != 2: return panic("positional write")
            let resized = value(handle.truncate(4))
            if value(handle.stat()).size != 4: return panic("handle stat")
            let sought = value(handle.seek(offset: 0, origin: 0))
            if value(read_all(input: handle.reader())) != "aXYd".to_bytes(): return panic("reader adapter")
        let closed: Result[Bytes, FileSystemError] = error(cause: FileSystemError.Closed)
        if handle.read_at(offset: 0, max_bytes: some(value: 1)) != closed: return panic("closed handle")
        handle.close()
