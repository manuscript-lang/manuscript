import control from "@std/process.ms"
import arguments from "@std/cli.ms"
import entropy from "@std/random.ms"
import filesystem from "@std/fs.ms"
import system from "@std/system.ms"
import wall_clock from "@std/time.ms"
import panic from "@std/faults.ms"
import uuid_v4 from "@std/random.ms"
import secure_int from "@std/random.ms"
import parse_timestamp from "@std/time.ms"
import Scheduler from "@std/tasks.ms"
import sleep from "@std/time.ms"
import posix from "@std/path.ms"
import win32 from "@std/path.ms"

fn timer_callback() Result[Unit, Error]:
    return ok(unit)

fn common_result[T, E: Error](result: Result[T, E]) Result[T, Error]:
    if let value = result: return ok(value)

    return error(Error(result.unwrap_error()))

fn exercise(path: String) Result[Unit, Error]:
    let written = try common_result(
        result: filesystem().write_file(
            path: path,
            data: "hello".to_bytes(),
            replace: false
        )
    )
    if not (
        try common_result(
            result: filesystem().read_file(path: path, max_bytes: 5)
        ) == "hello".to_bytes()
    ):
        return panic(message: "check failed")

    let info = try common_result(
        result: filesystem().stat(path: path, follow_links: true)
    )
    if not (info.size == 5):
        return panic(message: "check failed")
    if not (not info.directory):
        return panic(message: "check failed")

    let bytes = entropy().bytes(count: 16) | try common_result
    if not (bytes.length() == 16):
        return panic(message: "check failed")

    let identifier = uuid_v4(entropy: entropy()) | try common_result
    if not (identifier.byte_length() == 36):
        return panic(message: "check failed")

    let random = secure_int(entropy: entropy(), min: -2, max_exclusive: 3) | try common_result
    if not (random >= -2 and random < 3):
        return panic(message: "check failed")

    let now = wall_clock().now()
    if not ((now.to_string() | parse_timestamp | try common_result) == now):
        return panic(message: "check failed")
    if not (system().info().cpu_count > 0):
        return panic(message: "check failed")

    with file = try common_result(
        result: filesystem().open(path: path, flags: "r+", mode: 384)
    ):
        let updated = file.write_at(offset: 0, data: "HELLO".to_bytes()) | try common_result
        if not (
            try common_result(
                result: file.read_at(offset: 0, max_bytes: 5)
            ) == "HELLO".to_bytes()
        ):
            return panic(message: "positional I/O failed")

        let synced = file.sync() | try common_result
        let resized = file.truncate(size: 3) | try common_result
        if not ((try common_result(result: file.stat())).size == 3):
            return panic(message: "handle stat failed")

    with watcher = try common_result(
        result: filesystem().watch_native(
            path: path,
            recursive: false,
            max_entries: 4,
            max_events: 16,
            overflow: "error"
        )
    ):
        let appended = try common_result(
            result: filesystem().append_file(
                path: path,
                data: "!".to_bytes()
            )
        )
        let events = watcher.next() | try common_result
        if not (events.length() > 0):
            return panic(message: "native watch returned no event")

    with scheduler = Scheduler():
        let id = scheduler.after(duration: 0.milliseconds, operation: timer_callback) | try common_result
        sleep(duration: 10.milliseconds)

        match scheduler.status(id):
            Succeeded:
                let restarted = scheduler.restart(id) | try common_result
            Running:
                let restarted = scheduler.restart(id) | try common_result
            _:
                return panic(message: "scheduled work failed")

    let paths = posix()
    if not (
        try common_result(
            result: paths.resolve(base: "/work", parts: ["a", "../b"])
        ) == "/work/b"
    ):
        return panic(message: "path resolution failed")

    let windows = win32()
    if not (windows.parse("C:/work/file.txt").extension == ".txt"):
        return panic(message: "Windows path parse failed")

    let process_info = control().info() | try common_result
    if not (process_info.pid > 0):
        return panic(message: "process information failed")

    let memory = control().memory_usage() | try common_result
    if not (memory.heap_system > 0):
        return panic(message: "memory information failed")

    let removed = try common_result(
        result: filesystem().remove(path: path, recursive: false)
    )
    return ok(unit)

export fn main() Int:
    let path = match arguments().at(index: 0):
        some(path): path
        none:
            return 2

    if exercise(path: path).is_error(): return 1

    return 0
