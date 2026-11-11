// conform: tags=diagnostics
// conform: phase=check
test "interruptible":
    println("READY")
    while true:
        expect_equal(1, 1)?
test "later":
    fail("must not run")?
