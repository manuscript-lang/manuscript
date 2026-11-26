// conform: tags=formatter,testing,tier-core,try-result
// conform: phase=test,parse
// conform: origin=pkg/compiler/standalone_try_test.go:15 TestStandaloneTry
fn operation() Void! => ok()

test "valid" {
	operation()?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
