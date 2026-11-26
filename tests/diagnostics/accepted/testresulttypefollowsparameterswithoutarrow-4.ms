// conform: tags=diagnostics,formatter,interfaces,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/result_type_test.go:13 TestResultTypeFollowsParametersWithoutArrow
interface Read {
	fn read() Int
}
// expect-exit: 0
