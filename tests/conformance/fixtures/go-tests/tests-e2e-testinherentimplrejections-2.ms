# conform: tags=diagnostics,interfaces,tier-core
# conform: phase=check
# conform: origin=tests/e2e/inherent_methods_test.go:33 TestInherentImplRejections
interface I:
    fn f() Int
impl I:
    fn f() Int:
        return 1
