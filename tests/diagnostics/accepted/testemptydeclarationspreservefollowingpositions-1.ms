// conform: tags=diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/empty_declarations_test.go:49 TestEmptyDeclarationsPreserveFollowingPositions
type Empty { ... }

fn empty() Void { ... }

fn kept() Int {
	return 3
}
// expect-exit: 0
