import expect_equal, expect_false, expect_ok, expect_true from "@std/test/test.ms"
import TextError from "@std/core.ms"
import (
    ControlError,
    cpu_usage,
    groups,
    memory_usage,
    process_info,
    replace,
    resource_usage,
    set_groups,
    set_identity
) from "@std/os/process.ms"
import (
    FileSystemError,
    FileEvent,
    FileWatcher,
    join,
    create_directory,
    stat_filesystem,
    temporary,
    watch,
    watch_native,
    write_file
) from "@std/os/fs.ms"
import milliseconds, sleep from "@std/os/time.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import Shared from "@std/concurrency/shared.ms"

fn expect_process_error[T](outcome: T!ControlError, expected: ControlError) Unit!:
    match outcome:
        ok(_): return error(TextError("process misuse succeeded"))
        error(cause):
            if cause != expected: return error(TextError("wrong process error"))

    return ok(unit)

fn expect_fs_error[T](outcome: T!FileSystemError, expected: FileSystemError) Unit!:
    match outcome:
        ok(_): return error(TextError("filesystem misuse succeeded"))
        error(cause):
            if cause != expected: return error(TextError("wrong filesystem error"))

    return ok(unit)

test "process usage records report this process":
    let cpu = try cpu_usage()
    try expect_false(cpu.user_microseconds < 0 or cpu.system_microseconds < 0)

    let resources = try resource_usage()
    try expect_false(resources.max_resident_bytes <= 0)
    try expect_false(
        resources.user_microseconds < 0 or resources.involuntary_switches < 0
    )

    let memory = try memory_usage()
    try expect_false(memory.heap_used <= 0 or memory.resident <= 0)
    try expect_false(memory.heap_total < memory.heap_used)

test "set_identity and set_groups validate input and apply or refuse":
    try expect_process_error(
        set_identity(kind: "nope", id: 0), ControlError.InvalidInput
    )
    try expect_process_error(set_groups(groups: [-1]), ControlError.InvalidInput)

    let info = try process_info()

    if info.uid < 0:
        # Windows has no ids.
        try expect_process_error(
            set_identity(kind: "uid", id: 0), ControlError.Unsupported
        )
        try expect_process_error(set_groups(groups: [0]), ControlError.Unsupported)
    else:
        # Setting the identity it already has changes nothing and needs no privilege.
        try set_identity(kind: "uid", id: info.uid)
        try set_identity(kind: "gid", id: info.gid)
        try set_identity(kind: "euid", id: info.effective_uid)
        try set_identity(kind: "egid", id: info.effective_gid)

        let groups = try groups()

        if info.effective_uid == 0:
            try set_groups(groups: groups)
        else:
            try expect_process_error(
                set_groups(groups: groups), ControlError.PermissionDenied
            )

test "replace rejects invalid programs before leaving this process":
    let info = try process_info()
    let empty = replace(program: "", arguments: ["x"], environment: {})
    let missing = replace(
        program: "/definitely/not/a/program", arguments: ["x"], environment: {}
    )

    if info.uid < 0:
        # Windows has no exec.
        try expect_process_error(empty, ControlError.Unsupported)
        try expect_process_error(missing, ControlError.Unsupported)
    else:
        try expect_process_error(empty, ControlError.InvalidInput)
        try expect_process_error(missing, ControlError.NotFound)

test "stat_filesystem describes the filesystem under a path":
    let info = try stat_filesystem(path: ".")
    try expect_false(info.block_size <= 0 or info.blocks <= 0)
    try expect_false(info.blocks_available > info.blocks_free)
    try expect_fs_error(
        stat_filesystem(path: "/definitely/not/a/path"), FileSystemError.NotFound
    )

fn saw(events: List[FileEvent], path: String, kind: String) Bool:
    for event in events:
        if event.path == path and event.kind == kind: return true
    return false

test "polling and native watchers report a created file and close":
    let temporary = temporary("manuscript-watch-") | try expect_ok
    let root = temporary.path()
    var polling = try watch(path: root, recursive: false, interval: milliseconds(20))
    try write_file(path: "{root}/a.txt", data: "x", replace: false)
    try expect_true(saw(try polling.next(), join([root.clone(), "a.txt"]), "rename"))
    try polling.close()

    let native = try watch_native(path: root, recursive: false, overflow: "error")
    try write_file(path: "{root}/b.txt", data: "y", replace: false)

    var found = false
    for attempt in [1, 2, 3, 4, 5, 6]:
        if not found:
            found = saw(try native.next(), join([root.clone(), "b.txt"]), "rename")
    try expect_true(found)

test "native watcher max_entries counts the paths under the root":
    let t = temporary("ms-me-") | try expect_ok
    try write_file(path: "{t.path()}/a", data: "x", replace: false)
    try expect_fs_error(
        watch_native(
            path: t.path(), recursive: true, max_entries: 1, overflow: "error"
        ),
        FileSystemError.LimitExceeded
    )

    var w = try watch_native(
        path: t.path(), recursive: true, max_entries: 2, overflow: "error"
    )
    try w.close()

fn wait_next(w: Shared[FileWatcher]) Int:
    let r = w.next()
    if r.is_ok():
        return 1

    return 2

test "close wakes a pending native next with Closed":
    let t = temporary("ms-r2-") | try expect_ok
    var w: Shared[FileWatcher] = Shared(
        try watch_native(path: t.path(), recursive: false, overflow: "error")
    )
    var group = TaskGroup[Int]()
    let a = w
    group.spawn(fn var ch: wait_next(a))
    sleep(100.milliseconds)
    try w.close()

    let got = try group.results()
    try expect_equal(got[0], 2)

test "a group timeout cancels a task waiting on a watcher":
    let t = temporary("ms-r2-") | try expect_ok
    var w: Shared[FileWatcher] = Shared(
        try watch(path: t.path(), recursive: false, interval: milliseconds(20))
    )
    var group = TaskGroup[Int](timeout: 300.milliseconds)
    let a = w
    var h = group.spawn(fn var ch: wait_next(a))
    var c = group.spawn(fn var ch: 7)
    try expect_equal(c.result().get(-1), 7)
    try expect_true(h.result().is_error())
    try group.close()
    try w.close()

test "recursive native watch sees a file in a new subdirectory":
    let t = temporary("ms-r2-") | try expect_ok
    let r = t.path()
    var w = try watch_native(path: r, recursive: true, overflow: "error")
    try create_directory(path: "{r}/d", recursive: false)
    try write_file(path: "{r}/d/f", data: "1", replace: false)

    var seen = false
    for i in [1, 2, 3, 4, 5, 6, 7, 8]:
        if not seen:
            for e in try w.next():
                if e.path == join([r.clone(), "d", "f"]): seen = true
    try expect_true(seen)
