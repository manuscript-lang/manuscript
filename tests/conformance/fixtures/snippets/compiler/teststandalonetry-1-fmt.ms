# conform: tags=formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/standalone_try_test.go:10 TestStandaloneTry
fn operation() Unit!: ok(unit)

fn f() Int!:
    try operation()
    return ok(1)
