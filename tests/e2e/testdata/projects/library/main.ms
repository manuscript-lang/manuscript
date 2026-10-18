import {control, arguments} from "@std/process.ms"
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
    try filesystem().write_file(path, "hello".to_bytes(), replace: false)
    if not (try filesystem().read_file(path, 5) == "hello".to_bytes()):
        return panic("check failed")

    let info = try filesystem().stat(path, follow_links: true)
    if not (info.size == 5):
        return panic("check failed")
    if not (not info.directory):
        return panic("check failed")

    let bytes = try entropy().bytes(16)
    if not (bytes.length() == 16):
        return panic("check failed")

    let identifier = try uuid_v4(entropy())
    if not (identifier.byte_length() == 36):
        return panic("check failed")

    let random = try secure_int(entropy(), -2, 3)
    if not (random >= -2 and random < 3):
        return panic("check failed")

    let now = wall_clock().now()
    if not (try parse_timestamp(now.to_string()) == now):
        return panic("check failed")
    if not (system().info().cpu_count > 0):
        return panic("check failed")

    with file = try filesystem().open(path, "r+", 384):
        try file.write_at(0, "HELLO".to_bytes())
        if not (try file.read_at(0, 5) == "HELLO".to_bytes()):
            return panic("positional I/O failed")

        try file.sync()
        try file.truncate(3)
        if not ((try file.stat()).size == 3):
            return panic("handle stat failed")

    with watcher = try filesystem().watch_native(
        path,
        recursive: false,
        max_entries: 4,
        max_events: 16,
        overflow: "error"
    ):
        try filesystem().append_file(path, "!".to_bytes())
        let events = try watcher.next()
        if not (events.length() > 0):
            return panic("native watch returned no event")

    with scheduler = Scheduler():
        let id = try scheduler.after(0.milliseconds, timer_callback)
        sleep(10.milliseconds)

        match scheduler.status(id):
            Succeeded:
                try scheduler.restart(id)
            Running:
                try scheduler.restart(id)
            _:
                return panic("scheduled work failed")

    let paths = posix()
    if not (try paths.resolve("/work", ["a", "../b"]) == "/work/b"):
        return panic("path resolution failed")

    let windows = win32()
    if not (windows.parse("C:/work/file.txt").extension == ".txt"):
        return panic("Windows path parse failed")

    let process_info = try control().info()
    if not (process_info.pid > 0):
        return panic("process information failed")

    let memory = try control().memory_usage()
    if not (memory.heap_system > 0):
        return panic("memory information failed")

    try filesystem().remove(path, recursive: false)
    return ok(unit)

export fn main() Int:
    if let path = arguments().at(0):
        if exercise(path).is_error():
            return 1

        return 0
    else:
        return 2
