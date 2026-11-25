// conform: tags=formatter,generics,optional,testing,tier-core
// conform: phase=test,parse
// conform: origin=tests/e2e/testdata/accept/cl-09-2.ms
fn absent[T]() T? {
	return null
}

test "result context infers function arguments" {
	_value Int? := absent()
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
