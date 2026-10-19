# conform: tags=formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/standalone_try_test.go:10 TestStandaloneTry
fn operation() Result[Unit, Error]: ok(unit)
fn f() Result[Int, Error]:
    try operation()
    return ok(1)
