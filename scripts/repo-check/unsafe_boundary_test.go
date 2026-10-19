package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCheckUnsafeBoundary(t *testing.T) {
	root := t.TempDir()
	write := func(rel, src string) {
		p := filepath.Join(root, rel)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(src), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("crates/ms-rt/src/a.rs", "unsafe fn f() {}")
	write("crates/ms-cli/src/process.rs", "unsafe { x() }")
	write("crates/ms-syntax/src/ok.rs", "// the word unsafe in a comment is fine\nfn f() {}")
	write("crates/ms-syntax/src/bad.rs", "fn f() { unsafe { g() } }")
	write("crates/ms-check/src/bad.rs", "#![allow(unsafe_code)]")
	issues, err := checkUnsafeBoundary(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(issues) != 2 {
		t.Fatalf("want 2 issues, got %v", issues)
	}
}
