# conform: tags=formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/nested_literal_test.go:127 TestNestedUninferableConstructorReportsOnce
def f() -> Unit:
    let x = some(some(none))
