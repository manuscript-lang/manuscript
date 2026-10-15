package cli

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSearchFindsStandardAPIs(t *testing.T) {
	status, output, errors := invoke(t, "search", "jsn", "parse", "--limit", "2")
	if status != 0 || errors != "" || !strings.Contains(output, "@std/json.ms parse") || !strings.Contains(output, "fn parse(") {
		t.Fatalf("search: %d, %q, %q", status, output, errors)
	}
	status, output, _ = invoke(t, "search", "read", "file", "--json")
	var document struct {
		Format  int
		Query   string
		Matches []struct{ Module, Name, Signature string }
	}
	if err := json.Unmarshal([]byte(output), &document); err != nil || status != 0 || document.Format != 1 || document.Query != "read file" || len(document.Matches) != defaultSearchLimit {
		t.Fatalf("search --json: %d, %v, %+v", status, err, document)
	}
	status, output, _ = invoke(t, "search", "zzqxjv")
	if status != 0 || !strings.Contains(output, "No standard-library match") {
		t.Fatalf("no match: %d, %q", status, output)
	}
}

func TestSearchRejectsBadArguments(t *testing.T) {
	for _, args := range [][]string{{"search"}, {"search", "x", "--limit"}, {"search", "x", "--limit", "0"}, {"search", "x", "--bogus"}} {
		if status, _, errors := invoke(t, args...); status != 2 || errors == "" {
			t.Errorf("%v = %d, %q", args, status, errors)
		}
	}
	_, output, _ := invoke(t, "search", "list", "--limit=99", "--json")
	var document struct{ Matches []struct{ Name string } }
	if err := json.Unmarshal([]byte(output), &document); err != nil || len(document.Matches) != maxSearchLimit {
		t.Errorf("limit not capped at %d: %d matches, %v", maxSearchLimit, len(document.Matches), err)
	}
}

func TestSymbolReportsTypeDefinitionAndReferences(t *testing.T) {
	path := filepath.Join(t.TempDir(), "main.ms")
	source := "fn double(value: Int) -> Int:\n    return value * 2\n\nexport fn main() -> Int:\n    return double(4) - 8\n"
	if err := os.WriteFile(path, []byte(source), 0o644); err != nil {
		t.Fatal(err)
	}
	status, output, errors := invoke(t, "symbol", path+":5:12")
	if status != 0 || errors != "" || !strings.Contains(output, "type: double") || !strings.Contains(output, "defined: ") || !strings.Contains(output, "references (2)") {
		t.Fatalf("symbol: %d, %q, %q", status, output, errors)
	}
	status, output, _ = invoke(t, "symbol", path+":5:12", "--json")
	var document struct {
		Format     int
		Type       string
		Definition string
		References []string
	}
	if err := json.Unmarshal([]byte(output), &document); err != nil || status != 0 || document.Format != 1 || len(document.References) != 2 || !strings.HasSuffix(document.Definition, "main.ms:1:4") {
		t.Fatalf("symbol --json: %d, %v, %+v", status, err, document)
	}
}

func TestSymbolRejectsBadLocations(t *testing.T) {
	path := sourceFile(t, "export fn main() -> Int:\n    return 0\n")
	for _, args := range [][]string{{"symbol"}, {"symbol", "main.ms"}, {"symbol", "main.ms:0:1"}, {"symbol", "main.ms:x:1"}, {"symbol", path + ":1:1", "extra"}, {"symbol", path + ":1:1", "--bogus"}} {
		if status, _, errors := invoke(t, args...); status != 2 || errors == "" {
			t.Errorf("%v = %d, %q", args, status, errors)
		}
	}
	if status, _, errors := invoke(t, "symbol", path+":99:1"); status != 1 || !strings.Contains(errors, "past the end") {
		t.Errorf("past end = %d, %q", status, errors)
	}
	if status, _, errors := invoke(t, "symbol", "missing.ms:1:1"); status != 1 || !strings.Contains(errors, "file not found") {
		t.Errorf("missing = %d, %q", status, errors)
	}
}

func TestParseLocationAllowsColonsInPaths(t *testing.T) {
	file, line, column, ok := parseLocation(`C:\work\main.ms:12:7`)
	if !ok || file != `C:\work\main.ms` || line != 12 || column != 7 {
		t.Fatalf("parseLocation = %q %d %d %v", file, line, column, ok)
	}
}

func TestGuideTopics(t *testing.T) {
	status, output, _ := invoke(t, "guide")
	if status != 0 || !strings.Contains(output, "# Manuscript cheat sheet") {
		t.Fatalf("guide: %d, %.80q", status, output)
	}
	status, output, _ = invoke(t, "guide", "stdlib")
	if status != 0 || !strings.Contains(output, "## @std/json.ms") {
		t.Fatalf("guide stdlib: %d, %.80q", status, output)
	}
	status, output, _ = invoke(t, "guide", "stdlib", "json")
	if status != 0 || !strings.HasPrefix(output, "# @std/json.ms") {
		t.Fatalf("guide stdlib json: %d, %.80q", status, output)
	}
	for _, args := range [][]string{{"guide", "nope"}, {"guide", "stdlib", "nope"}, {"guide", "stdlib", "json", "fs"}} {
		if status, _, errors := invoke(t, args...); status != 2 || errors == "" {
			t.Errorf("%v = %d, %q", args, status, errors)
		}
	}
}
