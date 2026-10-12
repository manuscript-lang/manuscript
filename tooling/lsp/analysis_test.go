package lsp

import (
	"bytes"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestOverlayImportsAndNavigation(t *testing.T) {
	dir := t.TempDir()
	main := filepath.Join(dir, "main.ms")
	dep := filepath.Join(dir, "dep.ms")
	// Use the same local-import syntax exercised by compiler tests.
	source := "import answer from \"./dep.ms\"\nfn value() -> Int:\n    return answer()\n"
	if e := os.WriteFile(main, []byte(source), 0600); e != nil {
		t.Fatal(e)
	}
	original := "export fn answer() -> Int:\n    return 1\n"
	if e := os.WriteFile(dep, []byte(original), 0600); e != nil {
		t.Fatal(e)
	}
	uri := func(p string) string { return (&url.URL{Scheme: "file", Path: p}).String() }
	d := document{uri(main), source, 1}
	docs := map[string]document{d.URI: d, uri(dep): {uri(dep), "export fn answer() -> Int:\n    return 2\n", 2}}
	result := analyze(d, docs)
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	hover := navigation(result, d, position{2, 12}, "textDocument/hover")
	if hover == nil {
		t.Fatal("missing hover")
	}
	definition := navigation(result, d, position{2, 12}, "textDocument/definition")
	if definition == nil {
		t.Fatal("missing definition")
	}
	if len(references(result, d, position{2, 12})) != 2 {
		t.Fatal("missing reference")
	}
	data, _ := os.ReadFile(dep)
	if string(data) != original {
		t.Fatal("modified source")
	}
}

func TestDependencyChangesRefreshOpenDocuments(t *testing.T) {
	dir := t.TempDir()
	main := filepath.Join(dir, "main.ms")
	dep := filepath.Join(dir, "dep.ms")
	source := "import answer from \"./dep.ms\"\nfn value() -> Int:\n    return answer()\n"
	original := "export fn answer() -> Int:\n    return 1\n"
	os.WriteFile(main, []byte(source), 0600)
	os.WriteFile(dep, []byte(original), 0600)
	uri := func(p string) string { return (&url.URL{Scheme: "file", Path: p}).String() }
	d := document{uri(main), source, 1}
	other := document{uri(dep), original, 1}
	changed := other
	changed.Version = 2
	input := frame("textDocument/didOpen", nil, map[string]any{"textDocument": d}) + frame("textDocument/didOpen", nil, map[string]any{"textDocument": other}) + frame("textDocument/didChange", nil, map[string]any{"textDocument": changed, "contentChanges": []any{map[string]any{"text": "export fn answer() -> String:\n    return \"changed\"\n"}}}) + frame("shutdown", 1, nil) + frame("exit", nil, nil)
	var output bytes.Buffer
	if e := Serve(strings.NewReader(input), &output); e != nil {
		t.Fatal(e)
	}
	if !strings.Contains(output.String(), "\"severity\":1") || strings.Count(output.String(), "publishDiagnostics") != 5 {
		t.Fatal(output.String())
	}
}

func TestLocalRenameUsesBindingsAndVersions(t *testing.T) {
	source := "fn answer() -> Int:\n    let number = 42\n    return number\n"
	d := document{"file:///tmp/new-rename.ms", source, 5}
	result := analyze(d, map[string]document{d.URI: d})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	edit, err := rename(result, d, position{2, 12}, "value")
	if err != nil {
		t.Fatal(err)
	}
	changes := edit.(map[string]any)["documentChanges"].([]any)
	change := changes[0].(map[string]any)
	if len(change["edits"].([]any)) != 2 || change["textDocument"].(map[string]any)["version"] != 5 {
		t.Fatal(edit)
	}
	if _, err := rename(result, d, position{2, 12}, "answer"); err == nil {
		t.Fatal("accepted colliding name")
	}
	if _, err := rename(result, d, position{2, 12}, "not an identifier"); err == nil {
		t.Fatal("accepted invalid name")
	}
}
