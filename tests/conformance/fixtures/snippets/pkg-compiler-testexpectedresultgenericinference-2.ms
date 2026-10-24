# conform: tags=closures,diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/contextual_generics_test.go:45 TestExpectedResultGenericInference
def first() -> Unit:
    let callback: Callable[[], Optional[Int]] = lambda: absent()
