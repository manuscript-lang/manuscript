from "@std/testing.ms" import expect_false, expect_ok, expect_true
from "@std/core.ms" import TextError
from "@std/process.ms" import control, ProcessError
from "@std/fs.ms" import filesystem, FileSystemError, FileEvent
from "@std/time.ms" import milliseconds

def expect_process_error[T](
    outcome: Result[T, ProcessError],
    expected: ProcessError
) -> Result[Unit, Error]:
    match outcome:
        case ok(_): return error(TextError("process misuse succeeded"))
        case error(cause):
            if cause != expected: return error(TextError("wrong process error"))

    return ok(())

def expect_fs_error[T](
    outcome: Result[T, FileSystemError],
    expected: FileSystemError
) -> Result[Unit, Error]:
    match outcome:
        case ok(_): return error(TextError("filesystem misuse succeeded"))
        case error(cause):
            if cause != expected: return error(TextError("wrong filesystem error"))

    return ok(())

test "process usage records report this process":
    let process = control()
    let cpu = try process.cpu_usage()
    try expect_false(cpu.user_microseconds < 0 or cpu.system_microseconds < 0)

    let resources = try process.resource_usage()
    try expect_false(resources.max_resident_bytes <= 0)
    try expect_false(resources.user_microseconds < 0 or resources.involuntary_switches < 0)

    let memory = try process.memory_usage()
    try expect_false(memory.heap_used <= 0 or memory.resident <= 0)
    try expect_false(memory.heap_total < memory.heap_used)

test "set_identity and set_groups validate input and apply or refuse":
    let process = control()
    try expect_process_error(process.set_identity(kind: "nope", id: 0), ProcessError.InvalidInput)
    try expect_process_error(process.set_groups(groups: [-1]), ProcessError.InvalidInput)

    let info = try process.info()
    if info.uid < 0:
        # Windows has no ids.
        try expect_process_error(process.set_identity(kind: "uid", id: 0), ProcessError.Unsupported)
        try expect_process_error(process.set_groups(groups: [0]), ProcessError.Unsupported)
    else:
        # Setting the identity it already has changes nothing and needs no privilege.
        try process.set_identity(kind: "uid", id: info.uid)
        try process.set_identity(kind: "gid", id: info.gid)
        try process.set_identity(kind: "euid", id: info.effective_uid)
        try process.set_identity(kind: "egid", id: info.effective_gid)
        let groups = try process.groups()
        try process.set_groups(groups: groups)

test "replace rejects invalid programs before leaving this process":
    let process = control()
    let info = try process.info()
    let empty = process.replace(program: "", arguments: ["x"], environment: {})
    let missing = process.replace(
        program: "/definitely/not/a/program",
        arguments: ["x"],
        environment: {}
    )
    if info.uid < 0:
        # Windows has no exec.
        try expect_process_error(empty, ProcessError.Unsupported)
        try expect_process_error(missing, ProcessError.Unsupported)
    else:
        try expect_process_error(empty, ProcessError.InvalidInput)
        try expect_process_error(missing, ProcessError.NotFound)

test "stat_filesystem describes the filesystem under a path":
    let fs = filesystem()
    let info = try fs.stat_filesystem(path: ".")
    try expect_false(info.block_size <= 0 or info.blocks <= 0)
    try expect_false(info.blocks_available > info.blocks_free)
    try expect_fs_error(fs.stat_filesystem(path: "/definitely/not/a/path"), FileSystemError.NotFound)

def saw(events: List[FileEvent], path: String, kind: String) -> Bool:
    for event in events:
        if event.path == path and event.kind == kind: return True

    return False

test "polling and native watchers report a created file and close":
    let fs = filesystem()
    with let temporary = (fs.temporary("manuscript-watch-") | try expect_ok):
        let root = temporary.path()
        with let polling = try fs.watch(
            path: root, recursive: False, interval: milliseconds(20)
        ):
            try fs.write_file(path: f"{root}/a.txt", data: "x", replace: False)
            try expect_true(saw(try polling.next(), f"{root}/a.txt", "rename"))

        with let native = try fs.watch_native(
            path: root, recursive: False, overflow: "error"
        ):
            try fs.write_file(path: f"{root}/b.txt", data: "y", replace: False)
            var found = False
            for attempt in [1, 2, 3, 4, 5, 6]:
                if not found:
                    found = saw(try native.next(), f"{root}/b.txt", "rename")

            try expect_true(found)
