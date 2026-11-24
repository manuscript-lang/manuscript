// conform: tags=testing,tier-core,try-result
// conform: phase=test
// conform: origin=pkg/compiler/standalone_try_test.go:15 TestStandaloneTry
fn operation() Void! => ok()

test "valid":
    operation()?
