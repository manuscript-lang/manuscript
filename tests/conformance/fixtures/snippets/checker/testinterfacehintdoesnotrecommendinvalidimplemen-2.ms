# conform: tags=diagnostics,interfaces,tier-core
# conform: phase=check
# conform: origin=pkg/checker/interface_hints_test.go:97 TestInterfaceHintDoesNotRecommendInvalidImplementationReceivers
interface A:
    fn a() Int

interface B:
    fn b() Int

fn f(value: A) B: value
