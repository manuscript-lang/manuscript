# conform: tags=control-flow,formatter,interfaces,interpolation,modules,mutation,parser,records,stdlib-io,stdlib-testing,stdlib-time,strings,testing,tier-io,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/standard-contract-calls-reuse-operations-per-site.ms
import expect_true from "@std/test/test.ms"
import stdout from "@std/io/io.ms"
import monotonic from "@std/os/time.ms"

type Boom:
    code: Int

fn boom_error(boom: Boom) Error: Error("boom {boom.code}")

fn describe(e: Error) String: e.message

test "repeated calls through one site":
    var i = 0

    while i < 3:
        let a = monotonic()
        let b = monotonic()
        try expect_true((b.difference(other: a).to_milliseconds() >= 0))
        i = i + 1

    var out = stdout()
    var n = 0

    while n < 2:
        try expect_true((out.write(data: "x").is_ok()))
        n = n + 1

    try expect_true((describe(e: boom_error(Boom(code: 1))) == "boom 1"))
    try expect_true((describe(e: boom_error(Boom(code: 2))) == "boom 2"))
