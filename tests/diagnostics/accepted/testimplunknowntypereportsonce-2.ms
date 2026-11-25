// conform: tags=control-flow,diagnostics,formatter,interfaces,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/impl_unknown_type_test.go:17 TestImplUnknownTypeReportsOnce
type S {
	x Int
}

fn S.m() Int => return 1
// expect-exit: 0
