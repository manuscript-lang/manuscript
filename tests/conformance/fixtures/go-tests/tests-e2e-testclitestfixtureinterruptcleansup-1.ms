# conform: tags=control-flow,diagnostics,testing,tier-core,try-result
# conform: phase=check
# conform: origin=tests/e2e/test_fixture_test.go:196 TestCLITestFixtureInterruptCleansUp
test "interruptible":
    println("READY")
    while true:
        try expect_equal(1, 1)
test "later":
    try fail("must not run")
