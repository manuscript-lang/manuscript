from "@std/io.ms" import stderr, stdout
from "@std/test.ms" import expect_true

# The process's standard streams belong to the process: leaving a scope that bound one must not close it.
def writes_through_a_binding() -> Bool:
    var out = stdout()
    return out.write("").is_ok()

def writes_to_stderr_through_a_binding() -> Bool:
    var err = stderr()
    return err.write("").is_ok()

test "a binding of a standard stream does not close it at scope end":
    try expect_true(writes_through_a_binding())
    try expect_true(writes_through_a_binding())
    try expect_true(stdout().write("").is_ok())
    try expect_true(writes_to_stderr_through_a_binding())
    try expect_true(stderr().write("").is_ok())
