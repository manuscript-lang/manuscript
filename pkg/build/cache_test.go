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
