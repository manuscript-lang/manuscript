# conform: tags=diagnostics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/standalone_try_test.go:13 TestStandaloneTry
def operation() -> Result[Unit, Error]: ok(())

def f() -> Unit:
    try operation()
