package e2e_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestCLIRobustTestRunner(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "test.ms")
	source := `import {expect_equal, skip} from "@std/testing.ms"
test "passing":
    expect_equal(2 + 2, 4)
test "skipped":
    skip("fixture unavailable")
test "failing":
    expect_equal(1, 2)
test "later":
    expect_equal(true, true)
`
	if err := os.WriteFile(path, []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
	type report struct {
		Tests []struct {
			Name, Status string
			Index        int
			DurationNS   int64 `json:"duration_ns"`
		}
		Summary struct {
			Available, Selected, Passed, Failed, Skipped int
			NotRun                                       int `json:"not_run"`
		}
		Completed, Listed bool
	}
	run := func(args ...string) (int, report) {
		status, output, stderr := cliStreams(t, append([]string{"test", path, "--json"}, args...)...)
		var doc report
		if err := json.Unmarshal(output, &doc); err != nil {
			t.Fatalf("status %d: %v %s %s", status, err, output, stderr)
		}
		return status, doc
	}
	status, doc := run("--fail-fast")
	if status != 1 || !doc.Completed || doc.Summary.Passed != 1 || doc.Summary.Skipped != 1 || doc.Summary.Failed != 1 || doc.Summary.NotRun != 1 || doc.Tests[3].Status != "not_run" {
		t.Fatalf("fail fast %d %+v", status, doc)
	}
	status, doc = run("--match=passing|later", "--exclude=later", "--repeat=2", "--shuffle=42")
	if status != 0 || doc.Summary.Available != 4 || doc.Summary.Selected != 2 || doc.Summary.Passed != 2 || doc.Tests[1].Index != 1 || doc.Tests[0].DurationNS <= 0 {
		t.Fatalf("selection %d %+v", status, doc)
	}
	status, doc = run("--list")
	if status != 0 || !doc.Listed || doc.Summary.NotRun != 4 {
		t.Fatalf("list %d %+v", status, doc)
	}
	name := doc.Tests[0].Name
	cpu, heap, trace := filepath.Join(root, "cpu.pprof"), filepath.Join(root, "heap.pprof"), filepath.Join(root, "trace.out")
	status, doc = run("--test="+name, "--cpu-profile="+cpu, "--heap-profile="+heap, "--trace="+trace)
	if status != 0 || doc.Summary.Selected != 1 || doc.Tests[0].Name != name {
		t.Fatalf("profile %d %+v", status, doc)
	}
	for _, path := range []string{cpu, heap, trace} {
		if info, err := os.Stat(path); err != nil || info.Size() == 0 {
			t.Fatalf("missing profile %s: %v", path, err)
		}
	}
	for _, profile := range []string{cpu, heap} {
		if status, output, stderr := cliStreams(t, "pprof", "-top", profile); status != 0 {
			t.Fatalf("unreadable profile: %d %s %s", status, output, stderr)
		}
	}
	if status, output, stderr := cliStreams(t, "trace", "-d=parsed", trace); status != 0 {
		t.Fatalf("unreadable trace: %d %s %s", status, output, stderr)
	}
	// Failed assertions still flush requested collectors.
	heap = filepath.Join(root, "failed.pprof")
	status, doc = run("--match=::failing$", "--heap-profile="+heap)
	if status != 1 || doc.Summary.Failed != 1 {
		t.Fatalf("failed profile %d %+v", status, doc)
	}
	if info, err := os.Stat(heap); err != nil || info.Size() == 0 {
		t.Fatalf("failed profile missing: %v", err)
	}
}
