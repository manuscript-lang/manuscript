# conform: tags=diagnostics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/standalone_try_test.go:12 TestStandaloneTry
def operation() -> Result[Unit, Int]: ok(())

def f() -> Result[Int, Error]:
    try operation()
    return ok(1)
