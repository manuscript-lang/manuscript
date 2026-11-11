// conform: tags=diagnostics
// conform: phase=check
import expect_equal from "@std/test/test.ms"
test "failed assertion":
    2 + 3 | expect_equal(expected: 6)?
