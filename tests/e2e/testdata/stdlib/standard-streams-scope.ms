import (
	stderr, stdout from "@std/io/io.ms",
	expect_true from "@std/test/test.ms",
)

// The process's standard streams belong to the process: leaving a scope that bound one
// must not close it.
fn writes_through_a_binding() Bool:
	var out = stdout()
	return out.write("").is_ok()

fn writes_to_stderr_through_a_binding() Bool:
	var err = stderr()
	return err.write("").is_ok()

test "a binding of a standard stream does not close it at scope end":
	expect_true(writes_through_a_binding())?
	expect_true(writes_through_a_binding())?
	expect_true(stdout().write("").is_ok())?
	expect_true(writes_to_stderr_through_a_binding())?
	expect_true(stderr().write("").is_ok())?

test "closing a standard stream flushes it and leaves the process stream open":
	var out = stdout()
	out.write("")?

	_ := out.close()
	expect_true(stdout().write("").is_ok())?

	var err = stderr()
	_ := err.close()
	expect_true(stderr().write("").is_ok())?
