import {expect_equal, expect_false, expect_ok, fail} from "@std/testing.ms"
import {arguments, control} from "@std/process.ms"
import {stdin, stdout, stderr} from "@std/io.ms"
import {clock, wall_clock} from "@std/time.ms"
import entropy from "@std/random.ms"
import system from "@std/system.ms"
import network from "@std/net.ms"
import TaskGroup from "@std/tasks.ms"

fn check_services() Result[Unit, Error]:
    arguments().length() | try expect_equal(expected: 0)
    let before = clock().now()
    let after = clock().now()
    (after - before < 0.milliseconds) | try expect_false
    (wall_clock().now().unix_seconds() <= 0) | try expect_false
    (system().info().cpu_count <= 0) | try expect_false
    let variables = try control().environment()

    match entropy().bytes(0):
        ok(data):
            try expect_equal(data.length(), 0)
        error(_):
            return fail("entropy unavailable")

    return ok(unit)

test "host accessors work in callbacks and task executions":
    let check = check_services
    try check()

    with group = TaskGroup():
        let first = group.start(check)
        let second = group.start(check)
        let joined = try group.join()
        (try first.join()) | try expect_ok
        (try second.join()) | try expect_ok

test "repeated accessors retain closed root state":
    stdin().close()
    stdout().close()
    stderr().close()
    network().close()

    let cause = match stdout().write(""):
        ok(_):
            return fail("accessor reopened stdout")
        error(cause): cause

    match cause:
        Closed:
            return
        _:
            return fail("unexpected closed-stream error")

test "a later test receives fresh standard output":
    match stdout().write(""):
        ok(_):
            return
        error(_):
            return fail("another test closed this test's stdout")
