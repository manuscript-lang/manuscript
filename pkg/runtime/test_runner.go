package msruntime

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	goruntime "runtime"
	"strings"
	"time"

	"github.com/manuscript-lang/manuscript/internal/nativeabi"
)

// DefaultTestTimeout bounds each test run by the generated test executable
// so one deadlocked test cannot hang the whole run silently.
const DefaultTestTimeout = 60 * time.Second

// testCancelGrace is how long a timed-out test gets to unwind after
// cancellation before the runner abandons it and moves on.
const testCancelGrace = 2 * time.Second

// TestOptions selects and bounds the tests a run executes. A zero Timeout
// disables the per-test limit; a non-empty Filter keeps tests whose full
// name (module::name) contains it.
type TestOptions struct {
	Timeout time.Duration
	Filter  string
}

// ParseTestArgs reads --timeout=<duration> and --filter=<text> from the test
// executable's arguments; other arguments are ignored.
func ParseTestArgs(args []string) (TestOptions, error) {
	options := TestOptions{Timeout: DefaultTestTimeout}
	for _, arg := range args {
		switch {
		case strings.HasPrefix(arg, "--timeout="):
			timeout, err := time.ParseDuration(strings.TrimPrefix(arg, "--timeout="))
			if err != nil || timeout < 0 {
				return options, fmt.Errorf("invalid --timeout %q; use a duration such as 30s or 2m, or 0 to disable", strings.TrimPrefix(arg, "--timeout="))
			}
			options.Timeout = timeout
		case strings.HasPrefix(arg, "--filter="):
			options.Filter = strings.TrimPrefix(arg, "--filter=")
		}
	}
	return options, nil
}

// RunTests runs the test blocks with the options encoded in the executable's
// arguments and returns the number that failed (2 for an argument error).
func RunTests(tests []Test, args []string) int {
	reporter, err := openTestReporter()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	defer reporter.close()
	options, err := ParseTestArgs(args)
	if err != nil {
		reporter.emit(nativeabi.TestEvent{Event: "error", Reason: "argument_error", Failure: err.Error()})
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	return runTestsWith(tests, options, args, reporter)
}

// RunTestsWith runs tests with explicit options and no structured reporter.
func RunTestsWith(tests []Test, options TestOptions) int {
	return runTestsWith(tests, options, nil, nil)
}

func runTestsWith(tests []Test, options TestOptions, args []string, reporter *testReporter) int {
	total := len(tests)
	if options.Filter != "" {
		var selected []Test
		for _, test := range tests {
			if strings.Contains(test.Name, options.Filter) {
				selected = append(selected, test)
			}
		}
		tests = selected
	}
	if reporter != nil {
		names := make([]string, len(tests))
		for i, test := range tests {
			names[i] = test.Name
		}
		reporter.emit(nativeabi.TestEvent{Event: "plan", Format: 1, Available: total, Names: names})
	}
	if options.Filter != "" && len(tests) == 0 {
		reporter.emit(nativeabi.TestEvent{Event: "done", Reason: "no_match"})
		fmt.Printf("no tests match filter %q (%d tests available); the filter matches any part of a test's module::name\n", options.Filter, total)
		return 1
	}
	failed := 0
	for i, test := range tests {
		reporter.emit(nativeabi.TestEvent{Event: "run", Index: i})
		fmt.Printf("RUN %s\n", test.Name)
		if failure := runTest(test, options.Timeout, args); failure != nil {
			failed++
			reporter.emit(nativeabi.TestEvent{Event: "failed", Index: i, Failure: fmt.Sprint(failure)})
			fmt.Printf("FAIL %s: %v\n", test.Name, failure)
			continue
		}
		reporter.emit(nativeabi.TestEvent{Event: "passed", Index: i})
		fmt.Printf("PASS %s\n", test.Name)
	}
	if len(tests) == 0 {
		fmt.Println("no test blocks found: add test blocks to test.ms or *_test.ms files in the project, or pass a .ms file")
	}
	fmt.Printf("%d tests, %d failed\n", len(tests), failed)
	reason := ""
	if len(tests) == 0 {
		reason = "no_tests"
	}
	reporter.emit(nativeabi.TestEvent{Event: "done", Reason: reason})
	FlushDiagnostics()
	return failed
}

// runTest executes one test on its own root execution and returns its failure.
// When the timeout elapses the execution is cancelled; a test that still does
// not stop is abandoned after a goroutine dump so later tests can run.
func runTest(test Test, timeout time.Duration, args []string) any {
	testContext, cancel := context.WithCancel(context.Background())
	defer cancel()
	execution := rootExecution(testContext, args)
	done := make(chan any, 1)
	// An abandoned test keeps running beside later tests.
	go func() {
		var failure any
		defer func() { done <- failure }()
		defer func() {
			if r := recover(); r != nil {
				failure = r
			}
		}()
		if hostShutdown != nil {
			defer Cleanup(execution, hostShutdown)
		}
		defer FinishExecution(execution)
		test.Run(execution)
	}()
	if timeout <= 0 {
		return <-done
	}
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	select {
	case failure := <-done:
		return failure
	case <-timer.C:
	}
	cancel()
	select {
	case <-done:
		return fmt.Sprintf("timed out after %s; the test was cancelled (use --timeout to change the limit, 0 disables it)", timeout)
	case <-time.After(testCancelGrace):
	}
	stacks := make([]byte, 1<<20)
	stacks = stacks[:goruntime.Stack(stacks, true)]
	fmt.Fprintf(os.Stderr, "goroutines after timeout in %s:\n%s\n", test.Name, stacks)
	return fmt.Sprintf("timed out after %s and did not stop when cancelled; goroutine dump is on stderr", timeout)
}

type testReporter struct {
	file   *os.File
	failed bool
}

func openTestReporter() (*testReporter, error) {
	path := os.Getenv(nativeabi.TestEventsEnv)
	if path == "" {
		return nil, nil
	}
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
	if err != nil {
		return nil, fmt.Errorf("cannot record structured test results: %w", err)
	}
	return &testReporter{file: file}, nil
}

func (r *testReporter) emit(event nativeabi.TestEvent) {
	if r == nil || r.failed {
		return
	}
	if err := json.NewEncoder(r.file).Encode(event); err != nil {
		r.failed = true
		fmt.Fprintf(os.Stderr, "cannot record structured test results: %v\n", err)
	}
}

func (r *testReporter) close() {
	if r != nil {
		if err := r.file.Close(); err != nil {
			fmt.Fprintf(os.Stderr, "cannot close structured test results: %v\n", err)
		}
	}
}
