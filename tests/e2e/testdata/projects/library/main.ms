import expect_equal, expect_false, expect_true from "@std/test/test.ms"
import process_info from "@std/os/process.ms"
import memory_usage from "@std/os/system.ms"
import arguments from "@std/os/env.ms"
import random_bytes from "@std/random.ms"
import (
    OpenMode,
    OpenOptions,
    WatchOptions,
    append_file,
    open,
    read_file,
    remove,
    stat,
    watch,
    write_file
) from "@std/os/fs.ms"
import system_info from "@std/os/system.ms"
import now from "@std/time.ms"
import uuid_v4 from "@std/data/uuid.ms"
import secure_int from "@std/random.ms"
import parse_timestamp from "@std/time.ms"
import posix from "@std/os/path.ms"
import win32 from "@std/os/path.ms"

fn common_result[T](result: T!) T!: result

fn exercise(path: String) Unit!:
    _written := try common_result(
        result: write_file(path: path, data: "hello", replace: false).wait()
    )
    try expect_false(
        not (
            try common_result(
                result: read_file(path: path, max_bytes: 5).wait()
            ) == "hello".to_bytes()
        )
    )

    info := try common_result(result: stat(path: path))
    info.size | try expect_equal(5)
    (not info.is_directory()) | try expect_true

    bytes := try common_result(result: random_bytes(count: 16))
    bytes.length() | try expect_equal(16)

    identifier := try common_result(result: uuid_v4())
    identifier.byte_length() | try expect_equal(36)

    random := try common_result(result: secure_int(min: -2, max_exclusive: 3))
    (random >= -2 and random < 3) | try expect_true

    now := now()
    (try common_result(result: parse_timestamp(text: now.to_string()))) | try expect_equal(
        now
    )
    (system_info().cpu_count > 0) | try expect_true

    var file = try common_result(
        result: open(path, OpenMode.ReadWrite, OpenOptions(permissions: 384))
    )
    _updated := try common_result(result: file.write_at(offset: 0, data: "HELLO"))
    try expect_false(
        not (
            try common_result(
                result: file.read_at(offset: 0, max_bytes: 5)
            ) == "HELLO".to_bytes()
        )
    )

    _synced := try common_result(result: file.sync())
    _resized := try common_result(result: file.truncate(size: 3))
    (try common_result(result: file.stat())).size | try expect_equal(3)
    try file.close()

    var watcher = try common_result(
        result: watch(
            path: path,
            recursive: false,
            options: WatchOptions(
                max_entries: 4, max_events: 16, overflow: "error"
            )
        )
    )
    _appended := try common_result(result: append_file(path: path, data: "!").wait())
    events := try watcher.next()
    events.is_some() | try expect_true
    try watcher.close()

    paths := posix()
    try expect_false(
        not (
            try common_result(
                result: paths.resolve(
                    base: "/work", parts: ["a", "../b"]
                )
            ) == "/work/b"
        )
    )

    windows := win32()
    windows.parse("C:/work/file.txt").extension | try expect_equal(".txt")

    process_info := try common_result(result: process_info())
    (process_info.pid > 0) | try expect_true

    memory := try common_result(result: memory_usage())
    (memory.heap_system > 0) | try expect_true

    _removed := try common_result(result: remove(path: path, recursive: false))
    return ok(unit)

export fn main() Int:
    path := arguments().get(index: 0, default: "")
    if path == "": return 2

    match exercise(path: path):
        ok(_):
            return 0
        error(_):
            return 1
