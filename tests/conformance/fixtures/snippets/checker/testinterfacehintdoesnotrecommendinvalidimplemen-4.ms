# conform: tags=closures,diagnostics,interfaces,tier-core
# conform: phase=check
# conform: origin=pkg/checker/interface_hints_test.go:99 TestInterfaceHintDoesNotRecommendInvalidImplementationReceivers
interface Shape:
    fn area() Int

fn f(value: fn() Int) Shape: value
