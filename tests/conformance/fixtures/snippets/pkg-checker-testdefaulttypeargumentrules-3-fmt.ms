# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/default_type_arguments_test.go:25 TestDefaultTypeArgumentRules
def f[A = B, B = Int](value: B) -> B: value
