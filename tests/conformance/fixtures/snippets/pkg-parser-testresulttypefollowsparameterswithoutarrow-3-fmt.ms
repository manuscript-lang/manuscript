# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/result_type_test.go:12 TestResultTypeFollowsParametersWithoutArrow
def f() -> Int:
    let g = lambda (x) -> Int: x + 1
    let h = lambda x: x + 1
    return g(1) + h(2)
