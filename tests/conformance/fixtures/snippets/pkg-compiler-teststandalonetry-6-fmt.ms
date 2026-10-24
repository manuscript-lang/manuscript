# conform: tags=formatter,parser,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/standalone_try_test.go:15 TestStandaloneTry
def operation() -> Result[Unit, Error]: ok(())

test "valid":
    try operation()
