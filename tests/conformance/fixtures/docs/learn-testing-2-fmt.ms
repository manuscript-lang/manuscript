// conform: tags=formatter,modules,optional,parser,stdlib-json,stdlib-testing,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=documentation/learn/testing.md:53
import (
	parse from "@std/data/json.ms",
	expect_equal, expect_error, expect_ok, expect_some from "@std/test/test.ms",
)

test "typed JSON and Optional payloads":
	number := expect_ok(parse[Int]("3"))?
	expect_equal(number, 3)?
	expect_equal((expect_error(parse[Int]("true"))?).kind, "EBADMSG")?
	expect_some([number].first())? | expect_equal(3)?
