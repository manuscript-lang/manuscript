# conform: tags=formatter,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/interface_hints_test.go:96 TestInterfaceHintDoesNotRecommendInvalidImplementationReceivers
interface Shape:
    fn area() Int
fn f() Shape: 1
