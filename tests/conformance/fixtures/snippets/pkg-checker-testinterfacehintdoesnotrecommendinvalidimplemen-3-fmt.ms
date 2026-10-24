# conform: tags=formatter,generics,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/interface_hints_test.go:98 TestInterfaceHintDoesNotRecommendInvalidImplementationReceivers
interface Shape:
    def area() -> Int

def f[T](value: T) -> Shape: value
