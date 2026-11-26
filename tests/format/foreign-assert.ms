// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn f(x Int) Int {
    assert x == 1
    return 0
}
// expect-error: MS1000 5:5-5:11 there is no 'assert': in a test block write 'expect_equal(actual, expected)?' or 'expect_true(condition)?', imported from "@std/test/test.ms"
// expect-format-exit: 1
