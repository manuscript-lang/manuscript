import expect_false, expect_ok, expect_true from "@std/test/test.ms"
import PromiseOptions from "@std/concurrency/promise.ms"
import (
    cpu_usage,
    groups,
    process_info,
    replace,
    resource_usage,
    set_groups,
    IdentityKind,
    set_identity
) from "@std/os/process.ms"
import (memory_usage) from "@std/os/system.ms"
import (
    FileEvent,
    WatchOptions,
    create_directory,
    stat_filesystem,
    temporary,
    watch,
    write_file
) from "@std/os/fs.ms"
import join from "@std/os/path.ms"
import milliseconds from "@std/time.ms"
import ReadStream from "@std/io/io.ms"
import within from "./support/conn.ms"

fn expect_process_error[T](outcome: T!, expected: Error) Unit!:
    match outcome:
        ok(_): return error(Error("process misuse succeeded"))
        error(cause):
            if cause.kind != expected.kind: return error(Error("wrong process error"))

    return ok(unit)

fn expect_fs_error[T](outcome: T!, expected: Error) Unit!:
    match outcome:
        ok(_): return error(Error("filesystem misuse succeeded"))
        error(cause):
            if cause.kind != expected.kind: return error(
                Error("wrong filesystem error")
            )

    return ok(unit)

test "process usage records report this process":
    cpu := try cpu_usage()
    try expect_false(cpu.user_microseconds < 0 or cpu.system_microseconds < 0)

    resources := try resource_usage()
    try expect_false(resources.max_resident_bytes <= 0)
    try expect_false(
        resources.user_microseconds < 0 or resources.involuntary_switches < 0
    )

    memory := try memory_usage()
    try expect_false(memory.heap_used <= 0 or memory.resident <= 0)
    try expect_false(memory.heap_total < memory.heap_used)

test "set_identity and set_groups validate input and apply or refuse":
    try expect_process_error(
        set_identity(kind: IdentityKind.Uid, id: -1),
        Error("process: invalid input", kind: "EINVAL")
    )
    try expect_process_error(
        set_groups(groups: [-1]), Error("process: invalid input", kind: "EINVAL")
    )

    info := try process_info()

    if info.uid < 0:
        // Windows has no ids.
        try expect_process_error(
            set_identity(kind: IdentityKind.Uid, id: 0),
            Error("process: operation not supported", kind: "ENOTSUP")
        )
        try expect_process_error(
            set_groups(groups: [0]),
            Error("process: operation not supported", kind: "ENOTSUP")
        )
    else:
        // Setting the identity it already has changes nothing and needs no privilege.
        try set_identity(kind: IdentityKind.Uid, id: info.uid)
        try set_identity(kind: IdentityKind.Gid, id: info.gid)
        try set_identity(kind: IdentityKind.Euid, id: info.effective_uid)
        try set_identity(kind: IdentityKind.Egid, id: info.effective_gid)

        groups := try groups()

        if info.effective_uid == 0:
            try set_groups(groups: groups)
        else:
            try expect_process_error(
                set_groups(groups: groups),
                Error("process: permission denied", kind: "EACCES")
            )

test "replace rejects invalid programs before leaving this process":
    info := try process_info()
    empty := replace(program: "", arguments: ["x"], environment: {})
    missing := replace(
        program: "/definitely/not/a/program", arguments: ["x"], environment: {}
    )

    if info.uid < 0:
        // Windows has no exec.
        try expect_process_error(
            empty, Error("process: operation not supported", kind: "ENOTSUP")
        )
        try expect_process_error(
            missing, Error("process: operation not supported", kind: "ENOTSUP")
        )
    else:
        try expect_process_error(empty, Error("process: invalid input", kind: "EINVAL"))
        try expect_process_error(missing, Error("process: not found", kind: "ENOENT"))

test "stat_filesystem describes the filesystem under a path":
    info := try stat_filesystem(path: ".")
    try expect_false(info.block_size <= 0 or info.blocks <= 0)
    try expect_false(info.blocks_available > info.blocks_free)
    try expect_fs_error(
        stat_filesystem(path: "/definitely/not/a/path"),
        Error("filesystem: file or directory not found", kind: "ENOENT")
    )

// Reads events until one has `path` and `kind`, or `tries` events passed.
fn saw(var events: ReadStream[FileEvent], path: String, kind: String, tries: Int) Bool!:
    for attempt in 0..tries:
        next := try within(var events, 2.seconds())

        if event := next:
            if event.path == path and event.kind == kind: return ok(true)
        else:
            return ok(false)

    return ok(false)

test "polling and native watchers report a created file and close":
    temporary := temporary("manuscript-watch-") | try expect_ok
    root := temporary.path()
    var polling = try watch(
        path: root, recursive: false, options: WatchOptions(interval: milliseconds(20))
    )
    try write_file(path: "{root}/a.txt", data: "x", replace: false).wait()
    try expect_true(try saw(var polling, join([root.clone(), "a.txt"]), "rename", 8))
    try polling.close()

    var native = try watch(path: root, recursive: false)
    try write_file(path: "{root}/b.txt", data: "y", replace: false).wait()
    try expect_true(try saw(var native, join([root.clone(), "b.txt"]), "rename", 8))

test "native watcher max_entries counts the paths under the root":
    t := temporary("ms-me-") | try expect_ok
    try write_file(path: "{t.path()}/a", data: "x", replace: false).wait()
    try expect_fs_error(
        watch(
            path: t.path(), recursive: true, options: WatchOptions(max_entries: 1)
        ),
        Error("filesystem: limit exceeded", kind: "EOVERFLOW")
    )

    var w = try watch(
        path: t.path(), recursive: true, options: WatchOptions(max_entries: 2)
    )
    try w.close()

test "polling options reject native-only settings":
    t := temporary("ms-wo-") | try expect_ok
    polled := WatchOptions(interval: milliseconds(20))
    try expect_fs_error(
        watch(
            path: t.path(),
            options: WatchOptions(interval: milliseconds(20), max_events: 4)
        ),
        Error("filesystem: invalid input", kind: "EINVAL")
    )
    try expect_fs_error(
        watch(
            path: t.path(),
            options: WatchOptions(
                interval: milliseconds(20), overflow: "ignore"
            )
        ),
        Error("filesystem: invalid input", kind: "EINVAL")
    )
    try expect_fs_error(
        watch(path: t.path(), options: WatchOptions(overflow: "bogus")),
        Error("filesystem: invalid input", kind: "EINVAL")
    )

    var w = try watch(path: t.path(), options: polled)
    try w.close()

test "recursive native watch sees a file in a new subdirectory":
    t := temporary("ms-r2-") | try expect_ok
    r := t.path()
    var w = try watch(path: r, recursive: true)
    try create_directory(path: "{r}/d", recursive: false)
    try write_file(path: "{r}/d/f", data: "1", replace: false).wait()

    var seen = false
    for i in 0..8:
        if not seen:
            if e := try within(var w, 2.seconds()):
                if e.path == join([r.clone(), "d", "f"]): seen = true
    try expect_true(seen)
