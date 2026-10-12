import control from "@std/process.ms"
import arguments from "@std/cli.ms"
import entropy from "@std/random.ms"
import filesystem from "@std/fs.ms"
import system from "@std/system.ms"
import wall_clock from "@std/time.ms"
import panic from "@std/faults.ms"

import List from "@std/collections.ms"
import Result from "@std/result.ms"
import Error from "@std/errors.ms"
import uuid_v4 from "@std/random.ms"
import secure_int from "@std/random.ms"
import format_timestamp from "@std/time.ms"
import parse_timestamp from "@std/time.ms"
import after from "@std/time.ms"
import sleep from "@std/time.ms"
import posix from "@std/path.ms"
import win32 from "@std/path.ms"

fn timer_callback() -> Result[Unit, String]:
    return ok(value: unit)

fn common_result[T, E: Error](result: Result[T, E]) -> Result[T, Error]:
    match result:
        ok(value):
            return ok(value: value)
        error(cause):
            return error(cause: Error(value: cause))

fn exercise(path: String) -> Result[Unit, Error]:
    let written = try common_result(result: filesystem().write_file(path: path, data: "hello".to_bytes(), replace: false))
    if not (try common_result(result: filesystem().read_file(path: path, max_bytes: 5)) == "hello".to_bytes()):
        return panic(message: "check failed")
    let info = try common_result(result: filesystem().stat(path: path, follow_links: true))
    if not (info.size == 5):
        return panic(message: "check failed")
    if not (not info.directory):
        return panic(message: "check failed")
    let bytes = try common_result(result: entropy().bytes(count: 16))
    if not (bytes.length() == 16):
        return panic(message: "check failed")
    let identifier = try common_result(result: uuid_v4(entropy: entropy()))
    if not (identifier.byte_length() == 36):
        return panic(message: "check failed")
    let random = try common_result(result: secure_int(entropy: entropy(), min: -2, max_exclusive: 3))
    if not (random >= -2 and random < 3):
        return panic(message: "check failed")
    let now = wall_clock().now()
    if not (try common_result(result: parse_timestamp(text: format_timestamp(value: now))) == now):
        return panic(message: "check failed")
    if not (system().info().cpu_count > 0):
        return panic(message: "check failed")
    with file = try common_result(result: filesystem().open(path: path, flags: "r+", mode: 384)):
        let updated = try common_result(result: file.write_at(offset: 0, data: "HELLO".to_bytes()))
        if not (try common_result(result: file.read_at(offset: 0, max_bytes: 5)) == "HELLO".to_bytes()):
            return panic(message: "positional I/O failed")
        let synced = try common_result(result: file.sync())
        let resized = try common_result(result: file.truncate(size: 3))
        if not ((try common_result(result: file.stat())).size == 3):
            return panic(message: "handle stat failed")
    with watcher = try common_result(result: filesystem().watch_native(path: path, recursive: false, max_entries: 4, max_events: 16, overflow: "error")):
        let appended = try common_result(result: filesystem().append_file(path: path, data: "!".to_bytes()))
        let events = try common_result(result: watcher.next())
        if not (events.length() > 0):
            return panic(message: "native watch returned no event")
    with timer = try common_result(result: after(duration: 0.milliseconds, operation: timer_callback)):
        sleep(duration: 10.milliseconds)
        match timer.status():
            Succeeded:
                let restarted = try common_result(result: timer.restart())
            Running:
                let restarted = try common_result(result: timer.restart())
            _:
                return panic(message: "scheduled timer failed")
    let paths = posix()
    if not (try common_result(result: paths.resolve(base: "/work", parts: ["a", "../b"])) == "/work/b"):
        return panic(message: "path resolution failed")
    let windows = win32()
    if not (windows.parse("C:/work/file.txt").extension == ".txt"):
        return panic(message: "Windows path parse failed")
    let process_info = try common_result(result: control().info())
    if not (process_info.pid > 0):
        return panic(message: "process information failed")
    let memory = try common_result(result: control().memory_usage())
    if not (memory.heap_system > 0):
        return panic(message: "memory information failed")
    let removed = try common_result(result: filesystem().remove(path: path, recursive: false))
    return ok(value: unit)

export fn main() -> Int:
    match arguments().get(index: 0):
        some(path):
            match exercise(path: path):
                ok(_):
                    return 0
                error(_):
                    return 1
        none:
            return 2
