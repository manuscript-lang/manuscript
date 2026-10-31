# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/parser/positional_arguments_test.go:12 TestMixedArgumentsStrictAndPartial
fn run() Int:
    return select[Int](1, last: 3, fn value: value + 1)
