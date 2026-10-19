# conform: tags=formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/standalone_try_test.go:13 TestStandaloneTry
fn operation() Result[Unit, Error]: ok(unit)
fn f() Unit:
    try operation()
