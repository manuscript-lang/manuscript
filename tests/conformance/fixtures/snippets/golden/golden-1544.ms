// conform: tags=diagnostics
// conform: phase=check
import TestHooks, expect_equal from "@std/test/test.ms"
import stdout from "@std/io/io.ms"
type UnusedFixture:
    value: Int
impl TestHooks for UnusedFixture:
    fn before_all() Unit:
        written := stdout().write("UNUSED before_all").get()
    fn before_each() Unit:
        written := stdout().write("UNUSED before_each").get()
    fn after_each() Unit:
        written := stdout().write("UNUSED after_each").get()
    fn after_all() Unit:
        written := stdout().write("UNUSED after_all").get()
test "plain test":
    expect_equal(1 + 1, 2)?
