# conform: tags=control-flow,formatter,interfaces,interpolation,modules,mutation,parser,records,stdlib-io,stdlib-testing,stdlib-time,strings,testing,tier-io,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/standard-contract-calls-reuse-operations-per-site.ms
from "@std/testing.ms" import expect_true
from "@std/io.ms" import stdout
from "@std/time.ms" import clock

type Boom:
    code: Int

impl Error for Boom:
    def message() -> String: f"boom {self.code}"

def describe(e: Error) -> String: e.message()

test "repeated calls through one site":
    let c = clock()
    var i = 0

    while i < 3:
        let a = c.now()
        let b = c.now()
        try expect_true((b.difference(other: a).to_milliseconds() >= 0))
        i = i + 1

    var out = stdout()
    var n = 0

    while n < 2:
        try expect_true((out.write(data: "x").is_ok()))
        n = n + 1

    try expect_true((describe(e: Boom(code: 1)) == "boom 1"))
    try expect_true((describe(e: Boom(code: 2)) == "boom 2"))
