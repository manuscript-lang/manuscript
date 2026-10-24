# conform: tags=formatter,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/interface_hints_test.go:96 TestInterfaceHintDoesNotRecommendInvalidImplementationReceivers
interface Shape:
    def area() -> Int

def f() -> Shape: 1
