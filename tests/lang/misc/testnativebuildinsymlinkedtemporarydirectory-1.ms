// conform: tags=formatter,testing,tier-core
// conform: phase=test,parse
// conform: origin=pkg/build/library_test.go:275 TestNativeBuildInSymlinkedTemporaryDirectory
test "native module identity" {
	_value := 1
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
