# conform: tags=formatter,match,modules,parser,stdlib-io,stdlib-net,stdlib-process,stdlib-random,stdlib-system,stdlib-testing,stdlib-time,testing,tier-io,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/host-accessors.ms
import {expect_equal, expect_false, fail} from "@std/test.ms"
import {arguments, control} from "@std/process.ms"
import {stdin, stdout, stderr} from "@std/io.ms"
import {clock, wall_clock} from "@std/time.ms"
import entropy from "@std/random.ms"
import system from "@std/process.ms"
import network from "@std/net.ms"

fn check_services() Result[Unit, Error]:
    arguments().length() | try expect_equal(0)

    let before = clock().now()
    let after = clock().now()
    (after - before < 0.milliseconds) | try expect_false
    (wall_clock().now().unix_seconds() <= 0) | try expect_false
    (system().info().cpu_count <= 0) | try expect_false

    let _variables = try control().environment()

    match entropy().bytes(0):
        ok(data):
            try expect_equal(data.length(), 0)
        error(_):
            return fail("entropy unavailable")

    return ok(unit)

test "host accessors work in callbacks":
    let check = check_services
    try check()

test "closing a standard stream leaves the process stream open":
    stdin().close()
    stdout().close()
    stderr().close()
    network().close()

    match stdout().write(""):
        ok(_):
            return
        error(_):
            return fail("closing stdout closed the process stream")

test "a later test receives fresh standard output":
    match stdout().write(""):
        ok(_):
            return
        error(_):
            return fail("another test closed this test's stdout")
