# conform: tags=control-flow,diagnostics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/impl_unknown_type_test.go:17 TestImplUnknownTypeReportsOnce
type S:
    x: Int

impl Missing for S:
    fn m() Int: return 1
