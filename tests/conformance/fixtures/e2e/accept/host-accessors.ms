# conform: tags=match,modules,stdlib-io,stdlib-net,stdlib-process,stdlib-random,stdlib-system,stdlib-testing,stdlib-time,testing,tier-io,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/host-accessors.ms
import {expect_equal, expect_false, fail} from "@std/testing.ms"
import {arguments, control} from "@std/process.ms"
import {stdin, stdout, stderr} from "@std/io.ms"
import {clock, wall_clock} from "@std/time.ms"
import entropy from "@std/random.ms"
import system from "@std/process.ms"
import network from "@std/net.ms"

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

test "host accessors work in callbacks":
    let check = check_services
    try check()

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
