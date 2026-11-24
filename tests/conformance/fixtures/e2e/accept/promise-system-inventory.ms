// conform: tags=testing,tier-io
// conform: phase=test
import (
	promise, wait_all from "@std/concurrency/promise.ms",
	cpus, network_interfaces from "@std/os/system.ms",
	expect_equal from "@std/test/test.ms",
)

fn counts() Int!:
	c := cpus()?
	n := network_interfaces()?
	return ok(c.length() + n.length())

test "system inventories work from promises on any thread":
	here := counts().get_or(-1)
	all := wait_all(
		[promise(() => counts()), promise(() => counts()), promise(() => counts())]
	)
	for n in all.get_or([]):
		expect_equal(n, here)?
