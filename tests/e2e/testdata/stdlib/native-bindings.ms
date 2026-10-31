import expect_equal, expect_false, expect_ok, expect_true from "@std/test.ms"
import TextError from "@std/core.ms"
import control, ControlError from "@std/process.ms"
import filesystem, FileSystemError, FileEvent, FileWatcher, join from "@std/fs.ms"
import milliseconds, sleep from "@std/time.ms"
import TaskGroup from "@std/tasks.ms"
import Shared, share from "@std/shared.ms"

fn expect_process_error[T](
    outcome: Result[T, ControlError],
    expected: ControlError
) Result[Unit, Error]:
    match outcome:
        ok(_): return error(TextError("process misuse succeeded"))
        error(cause):
            if cause != expected: return error(TextError("wrong process error"))

    return ok(unit)

fn expect_fs_error[T](
    outcome: Result[T, FileSystemError],
    expected: FileSystemError
) Result[Unit, Error]:
    match outcome:
        ok(_): return error(TextError("filesystem misuse succeeded"))
        error(cause):
            if cause != expected: return error(TextError("wrong filesystem error"))

    return ok(unit)

test "process usage records report this process":
    let process = control()
    let cpu = try process.cpu_usage()
    try expect_false(cpu.user_microseconds < 0 or cpu.system_microseconds < 0)

    let resources = try process.resource_usage()
    try expect_false(resources.max_resident_bytes <= 0)
    try expect_false(
        resources.user_microseconds < 0 or resources.involuntary_switches < 0
    )

    let memory = try process.memory_usage()
    try expect_false(memory.heap_used <= 0 or memory.resident <= 0)
    try expect_false(memory.heap_total < memory.heap_used)

test "set_identity and set_groups validate input and apply or refuse":
    let process = control()
    try expect_process_error(
        process.set_identity(kind: "nope", id: 0), ControlError.InvalidInput
    )
    try expect_process_error(
        process.set_groups(groups: [-1]), ControlError.InvalidInput
    )

    let info = try process.info()

    if info.uid < 0:
        # Windows has no ids.
        try expect_process_error(
            process.set_identity(kind: "uid", id: 0), ControlError.Unsupported
        )
        try expect_process_error(
            process.set_groups(groups: [0]), ControlError.Unsupported
        )
    else:
        # Setting the identity it already has changes nothing and needs no privilege.
        try process.set_identity(kind: "uid", id: info.uid)
        try process.set_identity(kind: "gid", id: info.gid)
        try process.set_identity(kind: "euid", id: info.effective_uid)
        try process.set_identity(kind: "egid", id: info.effective_gid)

        let groups = try process.groups()

        if info.effective_uid == 0:
            try process.set_groups(groups: groups)
        else:
            try expect_process_error(
                process.set_groups(groups: groups), ControlError.PermissionDenied
            )

test "replace rejects invalid programs before leaving this process":
    let process = control()
    let info = try process.info()
    let empty = process.replace(program: "", arguments: ["x"], environment: {})
    let missing = process.replace(
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
    let fs = filesystem()
    let info = try fs.stat_filesystem(path: ".")
    try expect_false(info.block_size <= 0 or info.blocks <= 0)
    try expect_false(info.blocks_available > info.blocks_free)
    try expect_fs_error(
        fs.stat_filesystem(path: "/definitely/not/a/path"), FileSystemError.NotFound
    )

fn saw(events: List[FileEvent], path: String, kind: String) Bool:
    for event in events:
        if event.path == path and event.kind == kind: return true
    return false

test "polling and native watchers report a created file and close":
    let fs = filesystem()
    let temporary = fs.temporary("manuscript-watch-") | try expect_ok
    let root = temporary.path()
    var polling = try fs.watch(path: root, recursive: false, interval: milliseconds(20))
    try fs.write_file(path: "{root}/a.txt", data: "x", replace: false)
    try expect_true(saw(try polling.next(), join([root.clone(), "a.txt"]), "rename"))
    try polling.close()

    let native = try fs.watch_native(path: root, recursive: false, overflow: "error")
    try fs.write_file(path: "{root}/b.txt", data: "y", replace: false)

    var found = false
    for attempt in [1, 2, 3, 4, 5, 6]:
        if not found:
            found = saw(try native.next(), join([root.clone(), "b.txt"]), "rename")
    try expect_true(found)

test "native watcher max_entries counts the paths under the root":
    let fs = filesystem()
    let t = fs.temporary("ms-me-") | try expect_ok
    try fs.write_file(path: "{t.path()}/a", data: "x", replace: false)
    try expect_fs_error(
        fs.watch_native(
            path: t.path(), recursive: true, max_entries: 1, overflow: "error"
        ),
        FileSystemError.LimitExceeded
    )

    var w = try fs.watch_native(
        path: t.path(), recursive: true, max_entries: 2, overflow: "error"
    )
    try w.close()

fn wait_next(w: Shared[FileWatcher]) Int:
    let r = w.get().next()
    if r.is_ok():
        return 1

    return 2

test "close wakes a pending native next with Closed":
    let fs = filesystem()
    let t = fs.temporary("ms-r2-") | try expect_ok
    let w: Shared[FileWatcher] = share(
        try fs.watch_native(path: t.path(), recursive: false, overflow: "error")
    )
    let group = TaskGroup[Int]()
    let a = w
    group.spawn(fn ch: wait_next(a))
    sleep(100.milliseconds)
    try w.get().close()

    let got = try group.results()
    try expect_equal(got[0], 2)

test "a group timeout cancels a task waiting on a watcher":
    let fs = filesystem()
    let t = fs.temporary("ms-r2-") | try expect_ok
    let w: Shared[FileWatcher] = share(
        try fs.watch(
            path: t.path(), recursive: false, interval: milliseconds(20)
        )
    )
    var group = TaskGroup[Int](timeout: 300.milliseconds)
    let a = w
    let h = group.spawn(fn ch: wait_next(a))
    let c = group.spawn(fn ch: 7)
    try expect_equal(c.result().get(-1), 7)
    try expect_true(h.result().is_error())
    try group.close()
    try w.get().close()

test "recursive native watch sees a file in a new subdirectory":
    let fs = filesystem()
    let t = fs.temporary("ms-r2-") | try expect_ok
    let r = t.path()
    var w = try fs.watch_native(path: r, recursive: true, overflow: "error")
    try fs.create_directory(path: "{r}/d", recursive: false)
    try fs.write_file(path: "{r}/d/f", data: "1", replace: false)

    var seen = false
    for i in [1, 2, 3, 4, 5, 6, 7, 8]:
        if not seen:
            for e in try w.next():
                if e.path == join([r.clone(), "d", "f"]): seen = true
    try expect_true(seen)
