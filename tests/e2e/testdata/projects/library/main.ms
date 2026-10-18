import control from "@std/process.ms"
import arguments from "@std/cli.ms"
import {entropy, uuid_v4, secure_int} from "@std/random.ms"
import filesystem from "@std/fs.ms"
import system from "@std/system.ms"
import {wall_clock, parse_timestamp, sleep} from "@std/time.ms"
import panic from "@std/faults.ms"
import Scheduler from "@std/tasks.ms"
import {posix, win32} from "@std/path.ms"

fn timer_callback() Result[Unit, Error]:
    return ok(unit)

fn exercise(path: String) Result[Unit, Error]:
    try filesystem().write_file(path: path, data: "hello".to_bytes(), replace: false)
    if not (try filesystem().read_file(path: path, max_bytes: 5) == "hello".to_bytes()):
        return panic(message: "check failed")

    let info = try filesystem().stat(path: path, follow_links: true)
    if not (info.size == 5):
        return panic(message: "check failed")
    if not (not info.directory):
        return panic(message: "check failed")

    let bytes = try entropy().bytes(count: 16)
    if not (bytes.length() == 16):
        return panic(message: "check failed")

    let identifier = try uuid_v4(entropy: entropy())
    if not (identifier.byte_length() == 36):
        return panic(message: "check failed")

    let random = try secure_int(entropy: entropy(), min: -2, max_exclusive: 3)
    if not (random >= -2 and random < 3):
        return panic(message: "check failed")

    let now = wall_clock().now()
    if not (try parse_timestamp(text: now.to_string()) == now):
        return panic(message: "check failed")
    if not (system().info().cpu_count > 0):
        return panic(message: "check failed")

    with file = try filesystem().open(path: path, flags: "r+", mode: 384):
        try file.write_at(offset: 0, data: "HELLO".to_bytes())
        if not (try file.read_at(offset: 0, max_bytes: 5) == "HELLO".to_bytes()):
            return panic(message: "positional I/O failed")

        try file.sync()
        try file.truncate(size: 3)
        if not ((try file.stat()).size == 3):
            return panic(message: "handle stat failed")

    with watcher = try filesystem().watch_native(
        path: path,
        recursive: false,
        max_entries: 4,
        max_events: 16,
        overflow: "error"
    ):
        try filesystem().append_file(path: path, data: "!".to_bytes())
        let events = try watcher.next()
        if not (events.length() > 0):
            return panic(message: "native watch returned no event")

    with scheduler = Scheduler():
        let id = try scheduler.after(
            duration: 0.milliseconds,
            operation: timer_callback
        )
        sleep(duration: 10.milliseconds)

        match scheduler.status(id):
            Succeeded:
                try scheduler.restart(id)
            Running:
                try scheduler.restart(id)
            _:
                return panic(message: "scheduled work failed")

    let paths = posix()
    if not (try paths.resolve(base: "/work", parts: ["a", "../b"]) == "/work/b"):
        return panic(message: "path resolution failed")

    let windows = win32()
    if not (windows.parse("C:/work/file.txt").extension == ".txt"):
        return panic(message: "Windows path parse failed")

    let process_info = try control().info()
    if not (process_info.pid > 0):
        return panic(message: "process information failed")

    let memory = try control().memory_usage()
    if not (memory.heap_system > 0):
        return panic(message: "memory information failed")

    try filesystem().remove(path: path, recursive: false)
    return ok(unit)

export fn main() Int:
    if let path = arguments().at(index: 0):
        if exercise(path: path).is_error():
            return 1

        return 0
    else:
        return 2
