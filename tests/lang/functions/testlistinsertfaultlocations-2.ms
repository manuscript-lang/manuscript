// conform: tags=formatter,functions,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/list_parity_test.go:17 TestListInsertFaultLocations
export fn main() Int {
	var values = [1, 2]
	values.insert(-3, 9)
	return values.length()
}
// expect-exit: 134
// expect-stderr: List.insert: index must be between -2 and 2 (negative indexes count from the end), found -3
// expect-stderr:   at testlistinsertfaultlocations-2.ms:6 in main
