# conform: tags=diagnostics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/standalone_try_test.go:12 TestStandaloneTry
fn operation() Result[Unit, Int]: ok(unit)
fn f() Result[Int, Error]:
    try operation()
    return ok(1)
