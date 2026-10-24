# conform: tags=control-flow,formatter,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/impl_unknown_type_test.go:16 TestImplUnknownTypeReportsOnce
interface I:
    def m() -> Int

impl I for Missing:
    def m() -> Int: return 1
