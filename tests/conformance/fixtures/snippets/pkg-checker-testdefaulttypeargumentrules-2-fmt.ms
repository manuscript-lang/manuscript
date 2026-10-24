# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/default_type_arguments_test.go:24 TestDefaultTypeArgumentRules
def f[A = Int, B](value: B) -> B: value
