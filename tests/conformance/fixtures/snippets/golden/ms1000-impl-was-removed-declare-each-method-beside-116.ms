// conform: tags=diagnostics
// conform: phase=check
import TestHooks, expect_equal from "@std/test/test.ms"
import stdout from "@std/io/io.ms"
type UnusedFixture {
    value Int
}
impl TestHooks for UnusedFixture {
    fn before_all() Void {
        written := stdout().write("UNUSED before_all").get()
    }
    fn before_each() Void {
        written := stdout().write("UNUSED before_each").get()
    }
    fn after_each() Void {
        written := stdout().write("UNUSED after_each").get()
    }
    fn after_all() Void {
        written := stdout().write("UNUSED after_all").get()
    }
}
test "plain test" {
    expect_equal(1 + 1, 2)?
}
// expect-error: MS1000 8:1-8:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
