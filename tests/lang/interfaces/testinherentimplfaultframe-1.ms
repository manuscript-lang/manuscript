// conform: tags=formatter,interfaces,records,testing,tier-core
// conform: phase=test,parse
// conform: origin=tests/e2e/inherent_methods_test.go:14 TestInherentImplFaultFrame
type Counter {
	value Int
}

fn Counter.overflow() Int {
	return self.value * self.value
}

test "inherent fault frame" {
	Counter(value: 9223372036854775807).overflow()
}
// expect-exit: 1
// expect-tests: passed=0 failed=1
