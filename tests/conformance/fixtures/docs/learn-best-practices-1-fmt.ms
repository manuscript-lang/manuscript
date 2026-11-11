// conform: tags=formatter,interpolation,modules,parser,records,stdlib-json,stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=documentation/learn/best-practices.md:28
import (
	parse from "@std/data/json.ms",
	expect_equal, expect_error from "@std/test/test.ms",
)

type Config:
	port: Int = 8080

fn port_of(text: String) Result[Int, Error]:
	return ok(parse[Config](text)? | .port)

test "configuration defaults":
	expect_equal(port_of("\{\}")?, 8080)?
	expect_equal(port_of("\{\"port\": 9000\}")?, 9000)?

test "configuration rejects a wrong type":
	expect_equal((expect_error(parse[Config]("\{\"port\": true\}"))?).kind, "EBADMSG")?
