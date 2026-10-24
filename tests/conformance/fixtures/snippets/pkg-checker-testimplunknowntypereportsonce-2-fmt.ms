# conform: tags=control-flow,formatter,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/impl_unknown_type_test.go:17 TestImplUnknownTypeReportsOnce
type S:
    x: Int

impl Missing for S:
    def m() -> Int: return 1
