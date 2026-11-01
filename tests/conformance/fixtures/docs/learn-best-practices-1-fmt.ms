# conform: tags=formatter,interpolation,modules,parser,records,stdlib-json,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=documentation/learn/best-practices.md:28
import expect_equal, expect_error from "@std/test/test.ms"
import parse, JsonError from "@std/data/json.ms"

type Config:
    port: Int = 8080

fn port_of(text: String) Result[Int, Error]:
    return ok(try parse[Config](text) | .port)

test "configuration defaults":
    try expect_equal(try port_of("\{\}"), 8080)
    try expect_equal(try port_of("\{\"port\": 9000\}"), 9000)

test "configuration rejects a wrong type":
    try expect_error(parse[Config]("\{\"port\": true\}")) | try expect_equal(
        JsonError.InvalidData
    )
