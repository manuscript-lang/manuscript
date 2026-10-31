# conform: tags=formatter,parser,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/standalone_try_test.go:15 TestStandaloneTry
fn operation() Unit!: ok(unit)

test "valid":
    try operation()
