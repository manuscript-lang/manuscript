// conform: tags=control-flow,interfaces,interpolation,modules,mutation,records,stdlib-io,stdlib-testing,stdlib-time,strings,testing,tier-io,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/standard-contract-calls-reuse-operations-per-site.ms
import expect_true from "@std/test/test.ms"
import stdout from "@std/io/io.ms"
import monotonic from "@std/time.ms"

type Boom:
    code: Int

fn boom_error(boom: Boom) Error: Error("boom {boom.code}")

fn describe(e: Error) String: e.message

test "repeated calls through one site":
    var i = 0

    while i < 3:
        a := monotonic()
        b := monotonic()
        expect_true((b.difference(other: a).to_milliseconds() >= 0))?
        i = i + 1

    var out = stdout()
    var n = 0

    while n < 2:
        expect_true((out.write("x").is_ok()))?
        n = n + 1

    expect_true((describe(e: boom_error(Boom(code: 1))) == "boom 1"))?
    expect_true((describe(e: boom_error(Boom(code: 2))) == "boom 2"))?
