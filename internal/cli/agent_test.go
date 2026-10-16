package cli

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSearchFindsStandardAPIs(t *testing.T) {
	t.Chdir(t.TempDir())
	status, output, errors := invoke(t, "search_symbol", "jsn", "parse", "--limit", "2")
	if status != 0 || errors != "" || !strings.Contains(output, "json.parse") || !strings.Contains(output, "fn parse(") {
		t.Fatalf("search: %d, %q, %q", status, output, errors)
	}
	status, output, _ = invoke(t, "search_symbol", "read", "file", "--json")
	var document struct {
		Format  int
		Query   string
		Matches []struct{ Name, Origin, Signature string }
	}
	if err := json.Unmarshal([]byte(output), &document); err != nil || status != 0 || document.Format != 1 || document.Query != "read file" || len(document.Matches) != defaultSymbolLimit {
		t.Fatalf("search --json: %d, %v, %+v", status, err, document)
	}
	status, output, _ = invoke(t, "search_symbol", "zzqxjv")
	if status != 0 || !strings.Contains(output, "No project or standard-library symbol") {
		t.Fatalf("no match: %d, %q", status, output)
	}
}

func TestSingleWordFallsBackToSearch(t *testing.T) {
	t.Chdir(t.TempDir())
	status, output, _ := invoke(t, "search_symbol", "sleep")
	if status != 0 || !strings.Contains(output, "time.sleep") {
		t.Fatalf("search_symbol sleep: %d, %.120q", status, output)
	}
}

func TestSearchRejectsBadArguments(t *testing.T) {
	t.Chdir(t.TempDir())
	for _, args := range [][]string{{"search_symbol", "x", "--limit"}, {"search_symbol", "x", "--limit", "0"}, {"search_symbol", "x", "--bogus"}} {
		if status, _, errors := invoke(t, args...); status != 2 || errors == "" {
			t.Errorf("%v = %d, %q", args, status, errors)
		}
	}
	_, output, _ := invoke(t, "search_symbol", "list", "--limit=99", "--json")
	var document struct{ Matches []struct{ Name string } }
	if err := json.Unmarshal([]byte(output), &document); err != nil || len(document.Matches) != maxSymbolLimit {
		t.Errorf("limit not capped at %d: %d matches, %v", maxSymbolLimit, len(document.Matches), err)
	}
}

func TestSearchSymbolFindsDefinitionAndUses(t *testing.T) {
	root := t.TempDir()
	files := map[string]string{
		"ms.toml":      "[project]\nname = \"demo\"\nsource = \"./src\"\nentry = \"./src/main.ms\"\n",
		"src/main.ms":  "# Doubles a number.\nexport fn double(value: Int) -> Int:\n    return value * 2\n\nexport fn main() -> Int:\n    return double(4) - 8\n",
		"src/other.ms": "import {double} from \"./main.ms\"\nfn quad(v: Int) -> Int:\n    return double(double(v))\n",
	}
	for name, text := range files {
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	t.Chdir(root)
	status, output, errors := invoke(t, "search_symbol", "DOUBLE")
	want := filepath.Join("src", "main.ms") + ":2:11"
	if status != 0 || errors != "" || !strings.HasPrefix(output, "double  fn  "+want) || !strings.Contains(output, "# Doubles a number.") || !strings.Contains(output, "used (4)") || !strings.Contains(output, "other.ms:3:12") {
		t.Fatalf("search_symbol: %d, %q, %q", status, output, errors)
	}
	_, output, _ = invoke(t, "search_symbol", "double", "--json")
	var document struct {
		Format       int
		ProjectTotal int `json:"project_total"`
		Matches      []struct {
			Name, Kind, Definition, Doc string
			Uses                        []string
		}
	}
	if err := json.Unmarshal([]byte(output), &document); err != nil || document.Format != 1 || document.ProjectTotal != 1 || len(document.Matches) < 1 || len(document.Matches[0].Uses) != 4 {
		t.Fatalf("search_symbol --json: %v, %+v", err, document)
	}
	status, output, _ = invoke(t, "search_symbol", "dubel")
	if status != 0 || !strings.HasPrefix(output, "double  fn  ") {
		t.Errorf("fuzzy typo: %q", output)
	}
	status, output, _ = invoke(t, "search_symbol", "JSON_PARSE")
	if status != 0 || !strings.Contains(output, "json.parse") || !strings.Contains(output, "details: ms search_symbol json.parse") || len(output) > 3500 {
		t.Errorf("std symbol: %q", output)
	}
	if _, output, _ = invoke(t, "search_symbol", "zzqxjv"); !strings.Contains(output, "No project or standard-library symbol") {
		t.Errorf("no match: %q", output)
	}
	for _, args := range [][]string{{"search_symbol", "a", "--limit", "0"}, {"search_symbol", "a", "--bogus"}} {
		if status, _, errors := invoke(t, args...); status != 2 || errors == "" {
			t.Errorf("%v = %d, %q", args, status, errors)
		}
	}
}

func TestGuideIsOnlyTheCheatSheet(t *testing.T) {
	status, output, _ := invoke(t, "guide")
	if status != 0 || !strings.Contains(output, "# Manuscript cheat sheet") || !strings.Contains(output, "ms search_symbol") {
		t.Fatalf("guide: %d, %.80q", status, output)
	}
	if status, _, errors := invoke(t, "guide", "stdlib"); status != 2 || !strings.Contains(errors, "ms search_symbol") {
		t.Errorf("guide stdlib = %d, %q", status, errors)
	}
}

func TestStdPagesAreBoundedAndNavigable(t *testing.T) {
	t.Chdir(t.TempDir())
	status, output, errors := invoke(t, "search_symbol")
	if status != 0 || errors != "" || !strings.Contains(output, "prelude") || len(output) > 3500 {
		t.Fatalf("std: %d, %d bytes, %q", status, len(output), errors)
	}
	for _, c := range []struct{ arg, want string }{
		{"json", `import Name from "@std/json.ms"`},
		{"@std/json.ms", "fn parse"},
		{"prelude.List", "members ("},
		{"prelude.List.sorted", "sorted"},
	} {
		status, output, errors := invoke(t, "search_symbol", c.arg)
		if status != 0 || errors != "" || !strings.Contains(output, c.want) || len(output) > 4000 {
			t.Errorf("std %s: %d, %d bytes, %.80q, %q", c.arg, status, len(output), output, errors)
		}
	}
	for _, args := range [][]string{{"search_symbol", "--bogus"}, {"search_symbol", "x", "--limit", "0"}} {
		if status, _, errors := invoke(t, args...); status != 2 || errors == "" {
			t.Errorf("%v = %d, %q", args, status, errors)
		}
	}
}
