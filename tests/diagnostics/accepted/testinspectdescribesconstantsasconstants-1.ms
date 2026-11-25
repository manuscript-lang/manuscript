// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/inspect_constants_test.go:10 TestInspectDescribesConstantsAsConstants
LIMIT := 10

fn size() Int {
	return LIMIT
}
// expect-exit: 0
