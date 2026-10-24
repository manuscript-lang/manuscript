# conform: tags=closures,formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/contextual_generics_test.go:45 TestExpectedResultGenericInference
def first() -> Unit:
    let callback: Callable[[], Optional[Int]] = lambda: absent()
