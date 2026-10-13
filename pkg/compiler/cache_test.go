package compiler

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestAtomicWriteFailurePreservesDestinationAndRemovesStaging(t *testing.T) {
	root := t.TempDir()
	target := filepath.Join(root, "destination")
	if err := os.Mkdir(target, 0700); err != nil {
		t.Fatal(err)
	}
	marker := filepath.Join(target, "original")
	if err := os.WriteFile(marker, []byte("keep"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := atomicWrite(target, []byte("replacement"), 0600); err == nil {
		t.Fatal("replaced a populated directory")
	}
	contents, err := os.ReadFile(marker)
	if err != nil || string(contents) != "keep" {
		t.Fatal("failed publication changed the destination", err)
	}
	entries, err := os.ReadDir(root)
	if err != nil || len(entries) != 1 || entries[0].Name() != "destination" {
		t.Fatal("staging file leaked", entries, err)
	}
}

func TestShellQuoteKeepsLockHintsPasteable(t *testing.T) {
	for path, want := range map[string]string{
		"/tmp/proj/ms.toml":    "/tmp/proj/ms.toml",
		"/tmp/my proj/ms.toml": `"/tmp/my proj/ms.toml"`,
		`/tmp/a"b/ms.toml`:     `"/tmp/a\"b/ms.toml"`,
	} {
		if got := shellQuote(path); got != want {
			t.Fatalf("%s: got %s, want %s", path, got, want)
		}
	}
}

func TestCompilerPanicBecomesDiagnostic(t *testing.T) {
	result := func() (result Result) {
		defer recoverCompilerBug("a.ms", &result)
		panic("boom")
	}()
	if result.Success() || len(result.Diagnostics) != 1 || result.Diagnostics[0].Position.File != "a.ms" || !strings.Contains(result.Diagnostics[0].Message, "boom") {
		t.Fatalf("%+v", result.Diagnostics)
	}
}
