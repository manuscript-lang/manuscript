# conform: tags=modules,optional,stdlib-json,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=documentation/learn/testing.md:53
import {parse, JsonError} from "@std/json.ms"
import {expect_equal, expect_ok, expect_error, expect_some} from "@std/testing.ms"

test "typed JSON and Optional payloads":
    let number = try expect_ok(parse[Int]("3"))
    try expect_equal(number, 3)
    try expect_error(parse[Int]("true")) | try expect_equal(JsonError.InvalidData)
    try expect_some([number].first()) | try expect_equal(3)
