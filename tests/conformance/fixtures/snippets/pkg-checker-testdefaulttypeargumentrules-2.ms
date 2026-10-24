# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/default_type_arguments_test.go:24 TestDefaultTypeArgumentRules
def f[A = Int, B](value: B) -> B: value
