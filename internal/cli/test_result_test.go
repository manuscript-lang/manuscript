package cli

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/internal/nativeabi"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestJSONResultChildHelper(t *testing.T) {
	mode := os.Getenv("MS_JSON_RESULT_HELPER")
	if mode == "" {
		return
	}
	if mode == "partial" {
		file, err := os.Create(os.Getenv(nativeabi.TestEventsEnv))
		if err != nil {
			os.Exit(99)
		}
		encoder := json.NewEncoder(file)
		for _, event := range []nativeabi.TestEvent{
			{Event: "plan", Format: 1, Available: 3, Names: []string{"first", "stopped", "later"}},
			{Event: "run", Index: 0}, {Event: "passed", Index: 0}, {Event: "run", Index: 1},
		} {
			if encoder.Encode(event) != nil {
				os.Exit(99)
			}
		}
		file.Close()
	}
	fmt.Fprint(os.Stdout, "partial stdout")
	fmt.Fprint(os.Stderr, "partial stderr")
	if mode == "missing_success" {
		os.Exit(0)
	}
	os.Exit(23)
}

func TestJSONTestResultRetainsPartialExitAndStreams(t *testing.T) {
	for _, mode := range []string{"partial", "missing_failure", "missing_success"} {
		t.Run(mode, func(t *testing.T) {
			root := t.TempDir()
			out, err := os.Create(filepath.Join(root, "stdout"))
			if err != nil {
				t.Fatal(err)
			}
			defer out.Close()
			stderr, err := os.Create(filepath.Join(root, "stderr"))
			if err != nil {
				t.Fatal(err)
			}
			defer stderr.Close()
			originalOut, originalErr := os.Stdout, os.Stderr
			os.Stdout, os.Stderr = out, stderr
			defer func() { os.Stdout, os.Stderr = originalOut, originalErr }()
			child := exec.Command(os.Args[0], "-test.run=^TestJSONResultChildHelper$")
			child.Env = append(os.Environ(), "MS_JSON_RESULT_HELPER="+mode)
			status := runTestJSON(child, compiler.Result{SourceRoot: root})
			output, _ := os.ReadFile(out.Name())
			errors, _ := os.ReadFile(stderr.Name())
			var doc testResult
			want := 23
			if mode == "missing_success" {
				want = 1
			}
			if status != want || json.Unmarshal(output, &doc) != nil || doc.ExitCode != status || doc.Completed || doc.Reason != "execution_error" || doc.Stdout != "partial stdout" || !strings.HasPrefix(string(errors), "partial stderr") {
				t.Fatalf("%s: %d %s %s", mode, status, output, errors)
			}
			if mode == "partial" && (len(doc.Tests) != 3 || doc.Tests[0].Status != "passed" || doc.Tests[1].Status != "incomplete" || doc.Tests[2].Status != "not_run" || doc.Summary.Passed != 1 || doc.Summary.Failed != 0) {
				t.Fatalf("partial outcomes lost: %s", output)
			}
		})
	}
}

func TestTestJSONCompileFailureAndUnsupportedModes(t *testing.T) {
	file := sourceFile(t, "test \"broken\":\n    let x = unknown_name\n")
	status, output, stderr := invoke(t, "test", file, "--json")
	var doc testResult
	if status != 1 || stderr != "" || json.Unmarshal([]byte(output), &doc) != nil || doc.Completed || doc.Reason != "compile_error" || len(doc.Diagnostics) == 0 || doc.Diagnostics[0].Position.Line != 2 {
		t.Fatalf("compile JSON: %d %s %s", status, output, stderr)
	}
	for _, args := range [][]string{{"test", file, "--json", "--watch"}, {"test", file, "--json=true"}, {"run", file, "--json"}, {"fmt", file, "--json"}} {
		status, output, stderr := invoke(t, args...)
		if status != 2 || output != "" || stderr == "" {
			t.Fatalf("unsupported JSON %v: %d %s %s", args, status, output, stderr)
		}
	}
}
