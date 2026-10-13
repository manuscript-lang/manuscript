package e2e_test

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/build"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestListGoRangeStandalone(t *testing.T) {
	result := compiler.CompileFile("testdata/accept/list-go-range.ms", compiler.Options{Tests: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	source, err := build.Standalone(result.Source)
	if err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(t.TempDir(), "range")
	if err := build.Build(source, binary); err != nil {
		t.Fatal(err)
	}
	if output, err := commandOutput(t, binary); err != nil || !strings.Contains(string(output), "6 tests, 0 failed") {
		t.Fatalf("standalone range/interop cases: %v\n%s", err, output)
	}
}

func TestListShrinkConsumersStandalone(t *testing.T) {
	result := compiler.CompileFile("testdata/accept/list-shrink-consumers.ms", compiler.Options{Tests: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	source, err := build.Standalone(result.Source)
	if err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(t.TempDir(), "shrink")
	if err := build.Build(source, binary); err != nil {
		t.Fatal(err)
	}
	if output, err := commandOutput(t, binary); err != nil || !strings.Contains(string(output), "10 tests, 0 failed") {
		t.Fatalf("standalone typed shrink consumers: %v\n%s", err, output)
	}
}

func TestPrimitiveListStorageStandalone(t *testing.T) {
	result := compiler.CompileFile("testdata/accept/primitive-list-storage.ms", compiler.Options{Tests: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	source, err := build.Standalone(result.Source)
	if err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(t.TempDir(), "primitive-lists")
	if err := build.Build(source, binary); err != nil {
		t.Fatal(err)
	}
	if output, err := commandOutput(t, binary); err != nil || !strings.Contains(string(output), "3 tests, 0 failed") {
		t.Fatalf("standalone primitive Lists: %v\n%s", err, output)
	}
}
