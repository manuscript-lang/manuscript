# conform: tags=formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/standalone_try_test.go:11 TestStandaloneTry
fn operation() Int!: ok(1)

fn f() Int!:
    try operation()
    return ok(1)
