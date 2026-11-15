// conform: tags=formatter,parser,tier-core,try-result
// conform: phase=parse
// conform: origin=pkg/compiler/standalone_try_test.go:14 TestStandaloneTry
fn operation() Void: unit

fn f() Int!:
    operation()?
    return ok(1)
