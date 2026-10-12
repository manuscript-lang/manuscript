package main

import (
	"os"
	"strings"
	"testing"
)

func TestGeneratedReferenceCoverage(t *testing.T) {
	// The command intentionally runs at the repository root.
	t.Chdir("../..")
	files, err := generate()
	if err != nil {
		t.Fatal(err)
	}
	full := string(files["static/stdlib.md"])
	for _, signature := range []string{"# @std/http.ms", "# @std/cli.ms", "# prelude", "operation to_bytes:", "operation start:", "operation truncate_to_int:", "type parameters: T", "history_limit", "parallel_map"} {
		if !strings.Contains(full, signature) {
			t.Errorf("reference missing %q", signature)
		}
	}
	for path, want := range files {
		got, err := os.ReadFile(path)
		if err != nil {
			t.Error(err)
			continue
		}
		if string(got) != string(want) {
			t.Errorf("stale generated output: %s", path)
		}
	}
}
