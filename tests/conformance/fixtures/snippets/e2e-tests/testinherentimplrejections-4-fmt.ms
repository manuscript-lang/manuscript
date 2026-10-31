# conform: tags=formatter,generics,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/inherent_methods_test.go:35 TestInherentImplRejections
type B[T]:
    x: T

impl B:
    fn f() Int:
        return 1
