package rt

import "fmt"

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
		fmt.Printf("RUN %s\n", t.Name)
		if failure := runTest(t); failure != nil {
			failed++
			fmt.Printf("FAIL %s: %v\n", t.Name, failure)
			continue
		}
		fmt.Printf("PASS %s\n", t.Name)
	}
	fmt.Printf("%d tests, %d failed\n", len(tests), failed)
	return failed
}

func runTest(t Test) (failure any) {
	defer func() { failure = recover() }()
	t.Run(RootExecution())
	return nil
}

// Profile runs run under the requested CPU, heap and execution-trace
// profiles. The runtime core implements it (profile.go).
func Profile(cpu, heap, trace string, run func() int) int { return run() }
