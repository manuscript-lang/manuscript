// conform: tags=formatter,functions,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/list_parity_test.go:22 TestListInsertFaultLocations
fn main() Void {
	var values = [1]
	insert := values.insert
	insert(index: 5, value: 9)
}
