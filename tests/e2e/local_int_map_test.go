package e2e_test

import (
	"github.com/manuscript-lang/manuscript/pkg/build"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"path/filepath"
	"strings"
	"testing"
)

func TestClosedLocalIntMapStandalone(t *testing.T) {
	result := compiler.CompileFile("testdata/accept/closed-local-int-map.ms", compiler.Options{Tests: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	if !strings.Contains(result.Source, "rt.NewLocalIntMap(") {
		t.Fatal("fixture did not exercise local storage")
	}
	source, err := build.Standalone(result.Source)
	if err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(t.TempDir(), "local-map")
	if err := build.Build(source, binary); err != nil {
		t.Fatal(err)
	}
	if output, err := commandOutput(t, binary); err != nil || !strings.Contains(string(output), "5 tests, 0 failed") {
		t.Fatalf("standalone local maps: %v\n%s", err, output)
	}
}

func TestClosedIntListBoundsStandalone(t *testing.T) {
	result := compiler.CompileFile("testdata/accept/closed-int-list-bounds.ms", compiler.Options{Tests: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	source, err := build.Standalone(result.Source)
	if err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(t.TempDir(), "list-bounds")
	if err := build.Build(source, binary); err != nil {
		t.Fatal(err)
	}
	if output, err := commandOutput(t, binary); err != nil || !strings.Contains(string(output), "9 tests, 0 failed") {
		t.Fatalf("standalone list bounds: %v\n%s", err, output)
	}
}

func TestClosedRecordIntBoundsStandalone(t *testing.T) {
	result := compiler.CompileFile("testdata/accept/closed-record-int-bounds.ms", compiler.Options{Tests: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	if !strings.Contains(result.Source, "cell.Total = cell.Total ") {
		t.Fatal("fixture did not exercise proved field updates")
	}
	source, err := build.Standalone(result.Source)
	if err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(t.TempDir(), "record-bounds")
	if err := build.Build(source, binary); err != nil {
		t.Fatal(err)
	}
	if output, err := commandOutput(t, binary); err != nil || !strings.Contains(string(output), "5 tests, 0 failed") {
		t.Fatalf("standalone records: %v\n%s", err, output)
	}
}

func TestReadLinePresenceTailStandalone(t *testing.T) {
	result := compiler.CompileFile("testdata/accept/read-line-presence-tail.ms", compiler.Options{Tests: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	if !strings.Contains(result.Source, "rt.Io_HasLine(") {
		t.Fatal("fixture did not exercise payload elision")
	}
	source, err := build.Standalone(result.Source)
	if err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(t.TempDir(), "line-presence")
	if err := build.Build(source, binary); err != nil {
		t.Fatal(err)
	}
	if output, err := commandOutput(t, binary); err != nil || !strings.Contains(string(output), "4 tests, 0 failed") {
		t.Fatalf("standalone lines: %v\n%s", err, output)
	}
}
