# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/result_type_test.go:11 TestResultTypeFollowsParametersWithoutArrow
def f(g: Callable[[Int], Int]) -> Callable[[Int], Int]:
    return g
