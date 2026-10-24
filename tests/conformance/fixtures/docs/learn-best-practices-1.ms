# conform: tags=interpolation,modules,records,stdlib-json,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=documentation/learn/best-practices.md:28
from "@std/testing.ms" import expect_equal, expect_error
from "@std/json.ms" import parse, JsonError

type Config:
    port: Int = 8080

def port_of(text: String) -> Result[Int, Error]:
    return ok(try parse[Config](text) | .port)

test "configuration defaults":
    try expect_equal(try port_of("{}"), 8080)
    try expect_equal(try port_of("{\"port\": 9000}"), 9000)

test "configuration rejects a wrong type":
    try expect_error(parse[Config]("{\"port\": true}")) | try expect_equal(
        JsonError.InvalidData
    )
