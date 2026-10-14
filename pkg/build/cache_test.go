package build

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

func TestPinMismatchNamesWhatChanged(t *testing.T) {
	locked := BuildPin{1, "0.1.0", "aa", map[string]string{"GOOS": "linux", "GOARCH": "amd64"}}
	current := BuildPin{1, "0.2.0", "aa", map[string]string{"GOOS": "darwin", "GOARCH": "amd64"}}
	err := comparePin("/p", locked, current)
	if err == nil {
		t.Fatal("mismatch accepted")
	}
	for _, want := range []string{"compiler version (locked 0.1.0, current 0.2.0)", `toolchain GOOS (locked "linux", current "darwin")`, "ms lock /p/ms.toml"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("%q missing %q", err, want)
		}
	}
	if strings.Contains(err.Error(), "GOARCH") {
		t.Errorf("unchanged key reported: %q", err)
	}
}

func TestReadPinReportsNoGoInternals(t *testing.T) {
	for name, content := range map[string]string{"empty": "", "wrong type": `{"format": "1"}`} {
		root := t.TempDir()
		if err := os.WriteFile(filepath.Join(root, "ms.lock"), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
		_, err := readPin(root)
		if err == nil || strings.Contains(err.Error(), "BuildPin") || strings.Contains(err.Error(), "EOF") || !strings.Contains(err.Error(), "ms lock") {
			t.Errorf("%s: %v", name, err)
		}
	}
}

func TestOutputDirectoryIsCheckedBeforeBuilding(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "absent", "out")
	err := checkOutputDirectory(missing)
	if err == nil || !strings.Contains(err.Error(), missing) || strings.Contains(err.Error(), ".manuscript-write") {
		t.Fatalf("%v", err)
	}
	if err := checkOutputDirectory(filepath.Join(t.TempDir(), "out")); err != nil {
		t.Fatal(err)
	}
}
