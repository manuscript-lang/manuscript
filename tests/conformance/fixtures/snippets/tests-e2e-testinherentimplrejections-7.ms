# conform: tags=diagnostics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=tests/e2e/inherent_methods_test.go:38 TestInherentImplRejections
type B:
    x: Int
impl B:
    fn m() Int:
