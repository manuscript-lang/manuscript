// conform: tags=diagnostics,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/compiler/standalone_try_test.go:14 TestStandaloneTry
fn operation() Void => void

fn f() Int!:
    operation()?
    return ok(1)
