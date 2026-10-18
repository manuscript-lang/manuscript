package e2e_test

import (
	"context"
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/build"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

// Build the executable once, with a bounded setup, for all CLI conformance cases.
var cliBinary string

func TestMain(m *testing.M) {
	directory, err := os.MkdirTemp("", "manuscript-e2e-")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	cliBinary = filepath.Join(directory, "ms")
	tool, err := filepath.Abs("../../toolchain/go/bin/go")
	if err != nil {
		fmt.Fprintf(os.Stderr, "resolve conformance toolchain: %v\n", err)
		os.RemoveAll(directory)
		os.Exit(1)
	}
	if runtime.GOOS == "windows" {
		tool += ".exe"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	command := exec.CommandContext(ctx, tool, "build", "-o", cliBinary, "../../cmd/ms")
	output, err := command.CombinedOutput()
	cancel()
	status := 1
	if err != nil {
		fmt.Fprintf(os.Stderr, "build conformance CLI: %v\n%s", err, output)
	} else {
		status = m.Run()
	}
	os.RemoveAll(directory)
	os.Exit(status)
}
func commandOutput(t *testing.T, binary string, args ...string) ([]byte, error) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	data, err := exec.CommandContext(ctx, binary, args...).CombinedOutput()
	if ctx.Err() != nil {
		t.Fatalf("timed out: %s %v\n%s", binary, args, data)
	}
	return data, err
}

// A single path verifies checked source, native compilation, and execution.
func execute(t *testing.T, result compiler.Result, args ...string) ([]byte, error) {
	t.Helper()
	if !result.Success() {
		t.Fatalf("source rejected: %v", result.Diagnostics)
	}
	binary := filepath.Join(t.TempDir(), "program")
	if err := build.Build(result.Source, binary); err != nil {
		t.Fatal(err)
	}
	return commandOutput(t, binary, args...)
}
func rejected(t *testing.T, result compiler.Result, phase, message string) {
	t.Helper()
	if result.Success() {
		t.Fatal("invalid source was accepted")
	}
	for _, diagnostic := range result.Diagnostics {
		if diagnostic.Phase == phase && strings.Contains(diagnostic.Message, message) {
			return
		}
	}
	t.Fatalf("missing %s diagnostic containing %q: %v", phase, message, result.Diagnostics)
}
