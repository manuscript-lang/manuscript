// conform: tags=formatter,testing,tier-core
// conform: phase=test,parse
// conform: origin=pkg/compiler/standalone_try_test.go:16 TestStandaloneTry
test "bare" {
	return
}

test "unit" {
	return
}

test "fall" {
	_x := 1
}
// expect-exit: 0
// expect-tests: passed=3 failed=0
