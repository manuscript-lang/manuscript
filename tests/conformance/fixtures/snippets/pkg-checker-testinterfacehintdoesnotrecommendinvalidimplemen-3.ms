# conform: tags=diagnostics,generics,interfaces,tier-core
# conform: phase=check
# conform: origin=pkg/checker/interface_hints_test.go:98 TestInterfaceHintDoesNotRecommendInvalidImplementationReceivers
interface Shape:
    def area() -> Int

def f[T](value: T) -> Shape: value
