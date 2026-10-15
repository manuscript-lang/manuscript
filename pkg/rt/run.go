package rt

// Test is one test block of the generated program.
type Test struct {
	Name string
	Run  func(*Execution) Unit
}

// RunMain runs the program's main function and returns its exit status.
// The runtime core implements it (host.go).
func RunMain(main func(*Execution) int64, args []string) int {
	ctx := RootExecution()
	return int(main(ctx))
}

// RunTests runs the test blocks and returns the number that failed.
// The runtime core implements it (test_runner.go).
func RunTests(tests []Test, args []string) int {
	failed := 0
	for _, t := range tests {
		func() {
			defer func() {
				if r := recover(); r != nil {
					failed++
				}
			}()
			t.Run(RootExecution())
		}()
	}
	return failed
}
