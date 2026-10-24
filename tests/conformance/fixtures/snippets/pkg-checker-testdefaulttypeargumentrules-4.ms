# conform: tags=diagnostics,generics,interfaces,strings,tier-core
# conform: phase=check
# conform: origin=pkg/checker/default_type_arguments_test.go:26 TestDefaultTypeArgumentRules
interface Named:
    def name() -> String

def f[T: Named = Int]() -> Unit: ()
