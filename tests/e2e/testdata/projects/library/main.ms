import {expect_equal, expect_false, expect_true, fail} from "@std/testing.ms"
import control from "@std/process.ms"
import arguments from "@std/process.ms"
import entropy from "@std/random.ms"
import filesystem from "@std/fs.ms"
import system from "@std/process.ms"
import wall_clock from "@std/time.ms"
import uuid_v4 from "@std/random.ms"
import secure_int from "@std/random.ms"
import parse_timestamp from "@std/time.ms"
import posix from "@std/fs.ms"
import win32 from "@std/fs.ms"

fn common_result[T, E: Error](result: Result[T, E]) Result[T, Error]:
    match result:
        ok(value):
            return ok(value)
        error(cause):
            return error(Error(cause))

fn exercise(path: String) Result[Unit, Error]:
    let written = try common_result(
        result: filesystem().write_file(
            path: path, data: "hello", replace: false
        )
    )
    try expect_false(
        not (
            try common_result(
                result: filesystem().read_file(path: path, max_bytes: 5)
            ) == "hello".to_bytes()
        )
    )
    let info = try common_result(
        result: filesystem().stat(path: path, follow_links: true)
    )
    info.size | try expect_equal(expected: 5)
    (not info.directory) | try expect_true
    let bytes = try common_result(result: entropy().bytes(count: 16))
    bytes.length() | try expect_equal(expected: 16)
    let identifier = try common_result(result: uuid_v4(entropy: entropy()))
    identifier.byte_length() | try expect_equal(expected: 36)
    let random = try common_result(
        result: secure_int(entropy: entropy(), min: -2, max_exclusive: 3)
    )
    (random >= -2 and random < 3) | try expect_true
    let now = wall_clock().now()
    (try common_result(result: parse_timestamp(text: now.to_string()))) | try expect_equal(
        expected: now
    )
    (system().info().cpu_count > 0) | try expect_true

    with file = try common_result(
        result: filesystem().open(path: path, flags: "r+", mode: 384)
    ):
        let updated = try common_result(result: file.write_at(offset: 0, data: "HELLO"))
        try expect_false(
            not (
                try common_result(
                    result: file.read_at(offset: 0, max_bytes: 5)
                ) == "HELLO".to_bytes()
            )
        )
        let synced = try common_result(result: file.sync())
        let resized = try common_result(result: file.truncate(size: 3))
        (try common_result(result: file.stat())).size | try expect_equal(expected: 3)

    with watcher = try common_result(
        result: filesystem().watch_native(
            path: path, recursive: false, max_entries: 4, max_events: 16,
            overflow: "error"
        )
    ):
        let appended = try common_result(
            result: filesystem().append_file(path: path, data: "!")
        )
        let events = try common_result(result: watcher.next())
        (events.length() > 0) | try expect_true

    let paths = posix()
    try expect_false(
        not (
            try common_result(
                result: paths.resolve(
                    base: "/work", parts: ["a", "../b"]
                )
            ) == "/work/b"
        )
    )
    let windows = win32()
    windows.parse("C:/work/file.txt").extension | try expect_equal(expected: ".txt")
    let process_info = try common_result(result: control().info())
    (process_info.pid > 0) | try expect_true
    let memory = try common_result(result: control().memory_usage())
    (memory.heap_system > 0) | try expect_true
    let removed = try common_result(
        result: filesystem().remove(path: path, recursive: false)
    )
    return ok(unit)

export fn main() Int:
    let path = arguments().get(index: 0, default: "")
    if path == "": return 2

    match exercise(path: path):
        ok(_):
            return 0
        error(_):
            return 1
