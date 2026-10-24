# conform: tags=formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/standalone_try_test.go:11 TestStandaloneTry
def operation() -> Result[Int, Error]: ok(1)

def f() -> Result[Int, Error]:
    try operation()
    return ok(1)
