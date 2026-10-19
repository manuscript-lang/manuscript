# conform: tags=formatter,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/inherent_methods_test.go:36 TestInherentImplRejections
type B:
    x: Int
impl B:
    fn m[U](u: U) U:
        return u
