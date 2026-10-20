# conform: tags=diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/checker/nested_literal_test.go:127 TestNestedUninferableConstructorReportsOnce
fn f() Unit:
    let x = some(some(none))
