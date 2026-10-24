# conform: tags=formatter,generics,interfaces,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/default_type_arguments_test.go:26 TestDefaultTypeArgumentRules
interface Named:
    def name() -> String

def f[T: Named = Int]() -> Unit: ()
