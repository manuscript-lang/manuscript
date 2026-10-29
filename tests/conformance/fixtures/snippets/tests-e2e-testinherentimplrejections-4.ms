# conform: tags=diagnostics,generics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=tests/e2e/inherent_methods_test.go:35 TestInherentImplRejections
type B[T]:
    x: T

impl B:
    fn f() Int:
        return 1
