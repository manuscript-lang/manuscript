# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/parser/positional_arguments_test.go:12 TestMixedArgumentsStrictAndPartial
def run() -> Int:
    return select[Int](1, last: 3, lambda value: value + 1)
