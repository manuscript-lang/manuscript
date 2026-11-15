// conform: tags=diagnostics,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/compiler/standalone_try_test.go:12 TestStandaloneTry
fn operation() Void!Int: ok(void)

fn f() Int!:
    operation()?
    return ok(1)
