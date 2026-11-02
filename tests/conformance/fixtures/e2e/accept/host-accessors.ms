# conform: tags=match,modules,stdlib-io,stdlib-net,stdlib-process,stdlib-random,stdlib-system,stdlib-testing,stdlib-time,testing,tier-io,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/host-accessors.ms
import expect_equal, expect_false, fail from "@std/test/test.ms"
import arguments, environment from "@std/os/process.ms"
import stdin, stdout, stderr from "@std/io/io.ms"
import monotonic, now from "@std/os/time.ms"
import random_bytes from "@std/os/random.ms"
import system_info from "@std/os/process.ms"

fn check_services() Unit!:
    arguments().length() | try expect_equal(0)

    let before = monotonic()
    let after = monotonic()
    (after - before < 0.milliseconds) | try expect_false
    (now().unix_seconds() <= 0) | try expect_false
    (system_info().cpu_count <= 0) | try expect_false

    let _variables = try environment()

    match random_bytes(0):
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
