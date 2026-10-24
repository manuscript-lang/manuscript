# conform: tags=formatter,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/inherent_methods_test.go:37 TestInherentImplRejections
type B:
    x: Int

impl B:
    def m() -> Int:
        return 1

impl B:
    def m() -> Int:
        return 2
