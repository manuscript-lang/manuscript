package msruntime

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/manuscript-lang/manuscript/internal/nativeabi"
	mathrand "math/rand"
	"os"
	"os/signal"
	"regexp"
	goruntime "runtime"
	"strconv"
	"strings"
	"syscall"
	"time"
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
	Timeout        time.Duration
	Filter         string
	Names          []string
	Match, Exclude string
	List, FailFast bool
	Repeat         int
	Shuffle        bool
	Seed           int64
}

// ParseTestArgs reads selection, listing, repetition, ordering, and timeout
// options from the test executable; application arguments remain ignored.
func ParseTestArgs(args []string) (TestOptions, error) {
	options := TestOptions{Timeout: DefaultTestTimeout, Repeat: 1}
	for _, arg := range args {
		switch {
		case arg == "--list":
			options.List = true
		case arg == "--fail-fast":
			options.FailFast = true
		case strings.HasPrefix(arg, "--test="):
			options.Names = append(options.Names, strings.TrimPrefix(arg, "--test="))
		case strings.HasPrefix(arg, "--match="), strings.HasPrefix(arg, "--exclude="):
			name, value, _ := strings.Cut(arg, "=")
			if _, err := regexp.Compile(value); err != nil {
				return options, fmt.Errorf("invalid %s: %v; supply a valid regular expression", name, err)
			}
			if name == "--match" {
				options.Match = value
			} else {
				options.Exclude = value
			}
		case strings.HasPrefix(arg, "--repeat="):
			n, err := strconv.Atoi(strings.TrimPrefix(arg, "--repeat="))
			if err != nil || n <= 0 {
				return options, fmt.Errorf("invalid --repeat; use a positive integer")
			}
			options.Repeat = n
		case strings.HasPrefix(arg, "--shuffle="):
			n, err := strconv.ParseInt(strings.TrimPrefix(arg, "--shuffle="), 10, 64)
			if err != nil {
				return options, fmt.Errorf("invalid --shuffle; use an integer seed")
			}
			options.Shuffle, options.Seed = true, n
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
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	return runTestsContext(tests, options, args, reporter, ctx)
}

// RunTestsWith runs tests with explicit options and no structured reporter.
func RunTestsWith(tests []Test, options TestOptions) int {
	return runTestsWith(tests, options, nil, nil)
}

func runTestsWith(tests []Test, options TestOptions, args []string, reporter *testReporter) int {
	return runTestsContext(tests, options, args, reporter, context.Background())
}

func runTestsContext(tests []Test, options TestOptions, args []string, reporter *testReporter, runContext context.Context) int {
	defer FlushDiagnostics()
	total := len(tests)
	match, err := regexp.Compile(options.Match)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	exclude, err := regexp.Compile(options.Exclude)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	selected := make([]Test, 0, len(tests))
	found := make(map[string]bool)
	for _, test := range tests {
		exact := len(options.Names) == 0
		for _, name := range options.Names {
			if name == test.Name {
				exact = true
				found[name] = true
			}
		}
		if exact && strings.Contains(test.Name, options.Filter) && match.MatchString(test.Name) && (options.Exclude == "" || !exclude.MatchString(test.Name)) {
			selected = append(selected, test)
		}
	}
	for _, name := range options.Names {
		if !found[name] {
			message := fmt.Sprintf("unknown test %q; use --list to find full module::name identities", name)
			reporter.emit(nativeabi.TestEvent{Event: "error", Reason: "no_match", Failure: message})
			fmt.Fprintln(os.Stderr, message)
			return 1
		}
	}
	if options.Shuffle {
		mathrand.New(mathrand.NewSource(options.Seed)).Shuffle(len(selected), func(i, j int) { selected[i], selected[j] = selected[j], selected[i] })
		fmt.Printf("shuffle seed: %d\n", options.Seed)
	}
	repeat := options.Repeat
	if repeat <= 0 {
		repeat = 1
	}
	tests = nil
	if options.List {
		repeat = 1
	}
	if len(selected) > 0 {
		for n := 0; n < repeat; n++ {
			tests = append(tests, selected...)
		}
	}
	names := make([]string, len(tests))
	for i, test := range tests {
		names[i] = test.Name
	}
	reporter.emit(nativeabi.TestEvent{Event: "plan", Format: 1, Available: total, Names: names, Repeat: repeat, Seed: options.Seed, Shuffled: options.Shuffle})
	if len(tests) == 0 && (options.Filter != "" || options.Match != "" || options.Exclude != "" || len(options.Names) > 0) {
		reporter.emit(nativeabi.TestEvent{Event: "done", Reason: "no_match"})
		fmt.Printf("no tests match selection (%d tests available); use --list to find full module::name identities\n", total)
		return 1
	}
	if options.List {
		for _, test := range tests {
			fmt.Println(test.Name)
		}
		reporter.emit(nativeabi.TestEvent{Event: "done", Reason: "listed"})
		return 0
	}
	failed, skipped, fixtureFailures := 0, 0, 0
	states := map[*TestFixture]*fixtureState{}
	var owners []*fixtureState
	fixtureFailure := func(state *fixtureState, phase string, failure any) {
		fixtureFailures++
		reporter.emit(nativeabi.TestEvent{Event: "fixture_failed", File: state.definition.File, Phase: phase, Failure: testFailureText(failure)})
		fmt.Printf("FAIL %s fixture %s: %v\n", state.definition.File, phase, testFailureText(failure))
	}

	start := time.Now()
	reason := ""
	for i, test := range tests {
		if runContext.Err() != nil {
			reason = "cancelled"
			break
		}
		var state *fixtureState
		if test.Fixture != nil {
			state = states[test.Fixture]
			if state == nil {
				ctx, cancel := context.WithCancel(runContext)
				owner := rootExecution(ctx, args)
				state = &fixtureState{definition: test.Fixture, owner: owner, cancel: cancel}
				states[test.Fixture] = state
				owners = append(owners, state)
				phase, outcome := state.setup(options.Timeout)
				if outcome.failure != nil {
					fixtureFailure(state, phase, outcome.failure)
					if outcome.abandoned {
						reason = "fixture_abandoned"
						break
					}
					if options.FailFast {
						reason = "fail_fast"
						break
					}
				}
			}
			if state.failed {
				continue
			}
			test = state.test(test)
		}
		reporter.emit(nativeabi.TestEvent{Event: "run", Index: i})
		fmt.Printf("RUN %s\n", test.Name)
		began := time.Now()
		failure := runTestContext(test, options.Timeout, runContext, args)
		event := nativeabi.TestEvent{Event: "passed", Index: i, DurationNS: time.Since(began).Nanoseconds()}
		switch value := failure.(type) {
		case testSkip:
			skipped++
			event.Event, event.Failure = "skipped", value.Reason
			fmt.Printf("SKIP %s: %s\n", test.Name, value.Reason)
		case nil:
			fmt.Printf("PASS %s\n", test.Name)
		default:
			failed++
			event.Event, event.Failure = "failed", testFailureText(failure)
			fmt.Printf("FAIL %s: %v\n", test.Name, testFailureText(failure))
		}
		reporter.emit(event)
		if state != nil {
			if timeout, ok := failure.(testTimeout); ok && timeout.abandoned {
				state.poisoned.Store(true)
				fixtureFailure(state, "test", failure)
				reason = "fixture_abandoned"
				break
			}
		}
		if failed > 0 && options.FailFast {
			reason = "fail_fast"
			break
		}
	}
	for i := len(owners) - 1; i >= 0; i-- {
		state := owners[i]
		if state.poisoned.Load() {
			continue
		}
		outcome := state.shutdown(options.Timeout)
		if outcome.failure != nil {
			fixtureFailure(state, "after_all", outcome.failure)
		}
	}
	if runContext.Err() != nil && reason == "" {
		reason = "cancelled"
	}
	if fixtureFailures > 0 && reason == "" {
		reason = "fixture_error"
	}
	if len(tests) == 0 {
		fmt.Println("no test blocks found: add test blocks to test.ms or *_test.ms files in the project, or pass a .ms file")
		reason = "no_tests"
	}
	if skipped == 0 {
		fmt.Printf("%d tests, %d failed\n", len(tests), failed)
	} else {
		fmt.Printf("%d tests, %d failed, %d skipped\n", len(tests), failed, skipped)
	}
	reporter.emit(nativeabi.TestEvent{Event: "done", Reason: reason, DurationNS: time.Since(start).Nanoseconds()})
	if reason == "cancelled" && failed+fixtureFailures == 0 {
		return 1
	}
	return failed + fixtureFailures
}

// runTest executes one test on its own root execution and returns its failure.
// When the timeout elapses the execution is cancelled; a test that still does
// not stop is abandoned after a goroutine dump so later tests can run.
func runTest(test Test, timeout time.Duration, args []string) any {
	return runTestContext(test, timeout, context.Background(), args)
}

func runTestContext(test Test, timeout time.Duration, parent context.Context, args []string) any {
	testContext, cancel := context.WithCancel(parent)
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
		if outcome := test.Run(execution); outcome.Failed {
			failure = testReturnedError(execution, outcome.Err)
		}
	}()
	var timer *time.Timer
	var elapsed <-chan time.Time
	if timeout > 0 {
		timer = time.NewTimer(timeout)
		elapsed = timer.C
		defer timer.Stop()
	}
	message := "test run cancelled"
	select {
	case failure := <-done:
		return failure
	case <-elapsed:
		message = fmt.Sprintf("timed out after %s; the test was cancelled (use --timeout to change the limit, 0 disables it)", timeout)
	case <-parent.Done():
	}
	cancel()
	select {
	case failure := <-done:
		if failure != nil {
			if _, cancelled := failure.(cancelled); !cancelled {
				message += "\nwhile cancelling: " + fmt.Sprint(failure)
			}
		}
		return testTimeout{message: message}
	case <-time.After(testCancelGrace):
	}
	stacks := make([]byte, 1<<20)
	stacks = stacks[:goruntime.Stack(stacks, true)]
	fmt.Fprintf(os.Stderr, "goroutines after timeout in %s:\n%s\n", test.Name, stacks)
	return testTimeout{message: message + " and did not stop when cancelled; goroutine dump is on stderr", abandoned: true}
}

// testTimeout preserves whether timed-out work actually joined.
type testTimeout struct {
	message   string
	abandoned bool
}

func (t testTimeout) String() string { return t.message }

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
