# conform: tags=formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/standalone_try_test.go:14 TestStandaloneTry
fn operation() Unit: unit

fn f() Int!:
    try operation()
    return ok(1)
