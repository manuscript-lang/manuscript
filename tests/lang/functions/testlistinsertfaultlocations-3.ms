// conform: tags=formatter,functions,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/list_parity_test.go:22 TestListInsertFaultLocations
fn main() Void {
	var values = [1]
	insert := values.insert
	insert(index: 5, value: 9)
}
// expect-exit: 134
// expect-stderr: List.insert: index must be between -1 and 1 (negative indexes count from the end), found 5
// expect-stderr:   at testlistinsertfaultlocations-3.ms:7 in main
