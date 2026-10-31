# conform: tags=diagnostics,interfaces,tier-core
# conform: phase=check
# conform: origin=pkg/checker/interface_hints_test.go:96 TestInterfaceHintDoesNotRecommendInvalidImplementationReceivers
interface Shape:
    fn area() Int

fn f() Shape: 1
