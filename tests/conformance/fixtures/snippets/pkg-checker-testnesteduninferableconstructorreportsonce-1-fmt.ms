# conform: tags=formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/nested_literal_test.go:127 TestNestedUninferableConstructorReportsOnce
fn f() Unit:
    let x = none
