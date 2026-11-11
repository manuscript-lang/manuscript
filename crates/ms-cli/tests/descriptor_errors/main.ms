import expect_equal, expect_ok, expect_error from "@std/test/test.ms"
import arguments from "@std/os/env.ms"
import spawn, process_info from "@std/os/process.ms"
import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

fn check_failed_writer(size: Int) Unit!:
    executable := (process_info()?).executable
    child := spawn(executable, ["exit"])?
    expect_equal((child.wait()?), 0)?

    var writer = child.stdin()
    written := writer.write("x".repeat(size).get().to_bytes())

    if size < 65536:
        written | expect_ok?
    else:
        failure := written | expect_error?
        expect_equal(failure.kind, "EIO")?

    for unused in 0..2:
        failure := writer.flush() | expect_error?
        expect_equal(failure.kind, "EIO")?
        expect_equal(failure.message.starts_with("write: os error "), true)?

    // A failed descriptor never queues more bytes or reports a later empty flush as successful.
    repeated := writer.write("again".to_bytes()) | expect_error?
    expect_equal(repeated.kind, "EIO")?

    closed := writer.close() | expect_error?
    expect_equal(closed.kind, "EIO")?
    writer.close() | expect_ok?

    after_close := writer.write("closed".to_bytes()) | expect_error?
    expect_equal(after_close.kind, "EBADF")?
    return ok(unit)

fn check_healthy_writer() Unit!:
    executable := (process_info()?).executable
    child := spawn(executable, ["echo"])?
    var writer = child.stdin()
    writer.write("healthy\n".to_bytes()) | expect_ok?
    writer.flush() | expect_ok?
    writer.close() | expect_ok?
    expect_equal((child.wait()?), 0)?

    draining_child := spawn(executable, ["read-large"])?
    var draining_writer = draining_child.stdin()
    draining_writer.write("x".repeat(1048577).get().to_bytes()) | expect_ok?
    draining_writer.flush() | expect_ok?
    draining_writer.close() | expect_ok?
    expect_equal((draining_child.wait()?), 0)?
    return ok(unit)

fn check_failed_close() Unit!:
    executable := (process_info()?).executable
    child := spawn(executable, ["exit"])?
    expect_equal((child.wait()?), 0)?

    var writer = child.stdin()
    writer.write("buffered".to_bytes()) | expect_ok?

    closed := writer.close() | expect_error?
    expect_equal(closed.kind, "EIO")?
    writer.close() | expect_ok?
    return ok(unit)

fn check_writers() Unit!:
    for size in [1, 65535, 65536, 1048576, 1048577]:
        check_failed_writer(size)?
    check_healthy_writer()?
    check_failed_close()?
    return ok(unit)

export fn main() Int:
    args := arguments()

    if not args.is_empty():
        if args[0] == "echo":
            var input = stdin()
            if input.next().get().get() != "healthy\n".to_bytes(): return 2

        if args[0] == "read-large":
            if read_all(stdin()).get() != "x".repeat(1048577).get().to_bytes(): return 3
        return 0

    result := check_writers()

    if result.is_error():
        print(result.err().message)
        return 1

    print("descriptor errors preserved")
    return 0
