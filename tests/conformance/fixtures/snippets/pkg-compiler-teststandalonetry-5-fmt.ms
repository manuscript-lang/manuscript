# conform: tags=formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/standalone_try_test.go:14 TestStandaloneTry
def operation() -> Unit: ()

def f() -> Result[Int, Error]:
    try operation()
    return ok(1)
