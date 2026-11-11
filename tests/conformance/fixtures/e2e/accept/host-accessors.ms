// conform: tags=match,modules,stdlib-io,stdlib-net,stdlib-process,stdlib-random,stdlib-system,stdlib-testing,stdlib-time,testing,tier-io,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/host-accessors.ms
import (
	stderr, stdin, stdout from "@std/io/io.ms",
	arguments, environment from "@std/os/env.ms",
	system_info from "@std/os/system.ms",
	random_bytes from "@std/random.ms",
	expect_equal, expect_false, fail from "@std/test/test.ms",
	monotonic, now from "@std/time.ms",
)

fn check_services() Unit!:
	arguments().length() | expect_equal(0)?

	before := monotonic()
	after := monotonic()
	(after - before < 0.milliseconds()) | expect_false?
	(now().unix_seconds() <= 0) | expect_false?
	(system_info().cpu_count <= 0) | expect_false?

	_variables := environment()?

	match random_bytes(0):
		ok(data):
			expect_equal(data.length(), 0)?
		error(_):
			return fail("entropy unavailable")

test "host accessors work in callbacks":
	check := check_services
	check()?

test "closing a standard stream leaves the process stream open":
	stdin().close()?
	stdout().close()?
	stderr().close()?

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
