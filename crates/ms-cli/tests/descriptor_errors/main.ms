import expect_equal, expect_ok, expect_error from "@std/test/test.ms"
import arguments from "@std/os/env.ms"
import spawn, process_info from "@std/os/process.ms"
import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

fn check_failed_writer(size: Int) Unit!:
    let executable = (try process_info()).executable
    let child = try spawn(executable, ["exit"])
    try expect_equal((try child.wait()), 0)

    var writer = child.stdin()
    let written = writer.write("x".repeat(size).get().to_bytes())

    if size < 65536:
        written | try expect_ok
    else:
        let failure = written | try expect_error
        try expect_equal(failure.kind, "EIO")

    for unused in 0..2:
        let failure = writer.flush() | try expect_error
        try expect_equal(failure.kind, "EIO")
        try expect_equal(failure.message.starts_with("write: os error "), true)

    // A failed descriptor never queues more bytes or reports a later empty flush as successful.
    let repeated = writer.write("again".to_bytes()) | try expect_error
    try expect_equal(repeated.kind, "EIO")

    let closed = writer.close() | try expect_error
    try expect_equal(closed.kind, "EIO")
    writer.close() | try expect_ok

    let after_close = writer.write("closed".to_bytes()) | try expect_error
    try expect_equal(after_close.kind, "EBADF")
    return ok(unit)

fn check_healthy_writer() Unit!:
    let executable = (try process_info()).executable
    let child = try spawn(executable, ["echo"])
    var writer = child.stdin()
    writer.write("healthy\n".to_bytes()) | try expect_ok
    writer.flush() | try expect_ok
    writer.close() | try expect_ok
    try expect_equal((try child.wait()), 0)

    let draining_child = try spawn(executable, ["read-large"])
    var draining_writer = draining_child.stdin()
    draining_writer.write("x".repeat(1048577).get().to_bytes()) | try expect_ok
    draining_writer.flush() | try expect_ok
    draining_writer.close() | try expect_ok
    try expect_equal((try draining_child.wait()), 0)
    return ok(unit)

fn check_failed_close() Unit!:
    let executable = (try process_info()).executable
    let child = try spawn(executable, ["exit"])
    try expect_equal((try child.wait()), 0)

    var writer = child.stdin()
    writer.write("buffered".to_bytes()) | try expect_ok

    let closed = writer.close() | try expect_error
    try expect_equal(closed.kind, "EIO")
    writer.close() | try expect_ok
    return ok(unit)

fn check_writers() Unit!:
    for size in [1, 65535, 65536, 1048576, 1048577]:
        try check_failed_writer(size)
    try check_healthy_writer()
    try check_failed_close()
    return ok(unit)

export fn main() Int:
    let args = arguments()

    if not args.is_empty():
        if args[0] == "echo":
            var input = stdin()
            if input.next().get().get() != "healthy\n".to_bytes(): return 2

        if args[0] == "read-large":
            if read_all(stdin()).get() != "x".repeat(1048577).get().to_bytes(): return 3
        return 0

    let result = check_writers()

    if result.is_error():
        print(result.err().message)
        return 1

    print("descriptor errors preserved")
    return 0
