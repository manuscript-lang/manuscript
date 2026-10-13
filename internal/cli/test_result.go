package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/manuscript-lang/manuscript/internal/nativeabi"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

type testResult struct {
	Format       int                 `json:"format"`
	SourceRoot   string              `json:"source_root"`
	Tests        []testCaseResult    `json:"tests"`
	Summary      testSummary         `json:"summary"`
	Completed    bool                `json:"completed"`
	ExitCode     int                 `json:"exit_code"`
	Reason       string              `json:"reason,omitempty"`
	Stdout       string              `json:"stdout"`
	StdoutBase64 string              `json:"stdout_base64,omitempty"`
	Diagnostics  []commandDiagnostic `json:"diagnostics"`
}

type testCaseResult struct {
	Name    string `json:"name"`
	Status  string `json:"status"`
	Failure string `json:"failure,omitempty"`
}

type testSummary struct {
	Available int `json:"available"`
	Selected  int `json:"selected"`
	Passed    int `json:"passed"`
	Failed    int `json:"failed"`
}

func newTestResult(result compiler.Result) testResult {
	document := testResult{Format: 1, SourceRoot: result.SourceRoot, Tests: []testCaseResult{}, Diagnostics: []commandDiagnostic{}, ExitCode: 1}
	for _, issue := range result.Diagnostics {
		document.Diagnostics = append(document.Diagnostics, sourceDiagnostic(issue))
	}
	return document
}

func testJSONError(filename string, result compiler.Result, phase string, err error) int {
	fmt.Fprintln(os.Stderr, err)
	document := newTestResult(result)
	document.Reason = phase + "_error"
	document.Diagnostics = append(document.Diagnostics, commandDiagnostic{Code: "MST001", Phase: phase, Message: err.Error(), Position: syntax.Position{File: filename, Line: 1, Column: 1}})
	return emitJSON(document, 1)
}

func runTestJSON(child *exec.Cmd, result compiler.Result) int {
	directory, err := os.MkdirTemp("", "manuscript-test-results-")
	if err != nil {
		return testJSONError(child.Path, result, "execution", err)
	}
	defer os.RemoveAll(directory)
	stdout, err := os.Create(filepath.Join(directory, "stdout"))
	if err != nil {
		return testJSONError(child.Path, result, "execution", err)
	}
	defer stdout.Close()
	events := filepath.Join(directory, "events.jsonl")
	child.Env = append(child.Environ(), nativeabi.TestEventsEnv+"="+events)
	child.Stdout, child.Stderr = stdout, os.Stderr
	status := 0
	if err := runWithSignals(child); err != nil {
		var exit *exec.ExitError
		if errors.As(err, &exit) {
			status = exit.ExitCode()
		} else {
			return testJSONError(child.Path, result, "execution", err)
		}
	}
	document := newTestResult(result)
	document.ExitCode = status
	// os.Exit preserves the previous launcher behavior for negative statuses;
	// describe the observable CLI process status in its JSON document.
	if status < 0 {
		document.ExitCode = 255
	}
	if _, err := stdout.Seek(0, io.SeekStart); err != nil {
		return testJSONError(child.Path, result, "execution", err)
	}
	output, err := io.ReadAll(stdout)
	if err != nil {
		return testJSONError(child.Path, result, "execution", err)
	}
	document.Stdout, document.StdoutBase64 = capturedOutput(output)
	if err := readTestEvents(events, &document); err != nil {
		document.Completed = false
		if document.Reason == "" {
			document.Reason = "execution_error"
		}
		// Abrupt exit is a partial run, not a missing successful test report.
		if status == 0 {
			fmt.Fprintf(os.Stderr, "cannot read structured test results: %v\n", err)
			document.ExitCode, status = 1, 1
		}
	}
	if !document.Completed && document.Reason == "" {
		document.Reason = "execution_error"
	}
	for i := range document.Tests {
		if document.Tests[i].Status == "running" {
			document.Tests[i].Status = "incomplete"
		}
	}
	return emitJSON(document, status)
}

func readTestEvents(path string, document *testResult) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	decoder := json.NewDecoder(file)
	planned := false
	for {
		var event nativeabi.TestEvent
		if err := decoder.Decode(&event); err != nil {
			if errors.Is(err, io.EOF) && (planned || document.Reason != "") {
				return nil
			}
			return err
		}
		if document.Completed {
			return fmt.Errorf("test events follow completion")
		}
		switch event.Event {
		case "plan":
			if planned || event.Format != 1 || event.Available < len(event.Names) {
				return fmt.Errorf("invalid test plan")
			}
			planned = true
			document.Summary.Available, document.Summary.Selected = event.Available, len(event.Names)
			for _, name := range event.Names {
				document.Tests = append(document.Tests, testCaseResult{Name: name, Status: "not_run"})
			}
		case "run", "passed", "failed":
			if !planned || event.Index < 0 || event.Index >= len(document.Tests) {
				return fmt.Errorf("invalid test event index")
			}
			item := &document.Tests[event.Index]
			if event.Event == "run" {
				if item.Status != "not_run" {
					return fmt.Errorf("test started twice")
				}
				item.Status = "running"
			} else {
				if item.Status != "running" {
					return fmt.Errorf("test result without a start")
				}
				item.Status, item.Failure = event.Event, event.Failure
				if event.Event == "passed" {
					document.Summary.Passed++
				} else {
					document.Summary.Failed++
				}
			}
		case "done":
			if !planned || document.Summary.Passed+document.Summary.Failed != document.Summary.Selected {
				return fmt.Errorf("test completion before all results")
			}
			document.Completed, document.Reason = true, event.Reason
		case "error":
			document.Reason = event.Reason
			document.Diagnostics = append(document.Diagnostics, commandDiagnostic{Code: "MST001", Phase: "execution", Message: event.Failure})
		default:
			return fmt.Errorf("unknown test event %q", event.Event)
		}
	}
}
