# conform: tags=formatter,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/interface_hints_test.go:97 TestInterfaceHintDoesNotRecommendInvalidImplementationReceivers
interface A:
    def a() -> Int

interface B:
    def b() -> Int

def f(value: A) -> B: value
