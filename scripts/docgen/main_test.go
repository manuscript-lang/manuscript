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
	full := string(files["website/static/stdlib.md"])
	for _, signature := range []string{"# @std/http.ms", "# @std/cli.ms", "# prelude", "fn to_bytes() -> Bytes", "fn start(operation: fn() -> Result[Unit, Error]) -> Result[OperationId, StartError]", "fn truncate_to_int() -> Optional[Int]", "type List[T]:", "history_limit"} {
		if !strings.Contains(full, signature) {
			t.Errorf("reference missing %q", signature)
		}
	}
	for path, want := range files {
		if downloads[path] {
			continue
		}
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
