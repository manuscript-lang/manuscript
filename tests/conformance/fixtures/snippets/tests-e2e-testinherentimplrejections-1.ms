# conform: tags=parser,records,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/inherent_methods_test.go:32 TestInherentImplRejections
type A:
    x: Int
    fn f() Int:
        return 1
