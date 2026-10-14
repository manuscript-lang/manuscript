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

func TestSelfDefinitionUsesItsMethodDeclaration(t *testing.T) {
	source := "interface Read:\n    fn get() -> Int\ntype Box:\n    value: Int\nimpl Read for Box:\n    fn get() -> Int:\n        return self.value\n"
	d := document{"file:///tmp/self.ms", source, 1}
	result := analyze(d, map[string]document{d.URI: d})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	target := navigation(result, d, Position(source, strings.Index(source, "self.value")), "textDocument/definition")
	if target == nil {
		t.Fatal("implicit receiver lost its definition")
	}
	r := target.([]any)[0].(map[string]any)["range"].(span)
	if r.Start != Position(source, strings.LastIndex(source, "fn get")+len("fn ")) {
		t.Fatal("implicit receiver points outside its method", target)
	}
}

func TestInvalidNestedManifestDoesNotInheritParentAliases(t *testing.T) {
	root := t.TempDir()
	for name, source := range map[string]string{
		"ms.toml":        "[project]\nname = \"parent\"\nsource = \".\"\nentry = \"main.ms\"\n[aliases]\n\"@parent\" = \".\"\n",
		"main.ms":        "",
		"nested/ms.toml": "invalid configuration",
		"nested/main.ms": "",
	} {
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(source), 0600); err != nil {
			t.Fatal(err)
		}
	}
	d := document{URI: fileURI(filepath.Join(root, "nested/main.ms"))}
	if p, ok := editorProject(d); ok || len(p.Aliases) != 0 {
		t.Fatal("completion silently selected an invalid project's parent", p)
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

func TestMultilineParameterNavigationDuringRecovery(t *testing.T) {
	for _, ending := range []string{"\n", "\r\n"} {
		source := strings.ReplaceAll("fn first() -> Int:\n    return 1\nexport fn answer(\n    input: Int,\n) -> Int:\n    return input\nfn broken(\n", "\n", ending)
		d := document{"file:///tmp/multiline.ms", source, 1}
		result := analyze(d, map[string]document{d.URI: d})
		if len(result.Diagnostics) != 1 || result.Diagnostics[0].Position.Line != 8 {
			t.Fatal(result.Diagnostics)
		}
		declaration := Position(source, strings.Index(source, "input:"))
		use := Position(source, strings.Index(source, "input"+ending))
		definition := navigation(result, d, use, "textDocument/definition")
		if definition == nil {
			t.Fatal("missing parameter definition")
		}
		r := definition.([]any)[0].(map[string]any)["range"].(span)
		if r.Start != declaration || navigation(result, d, declaration, "textDocument/hover") == nil {
			t.Fatal("incorrect parameter navigation", definition)
		}
		if len(references(result, d, use, true)) != 2 {
			t.Fatal("missing parameter reference")
		}
		symbols := documentSymbols(result, d)
		if len(symbols) != 2 || symbols[1].(map[string]any)["name"] != "answer" {
			t.Fatal("missing multiline function symbol", symbols)
		}
		// Rename intentionally requires a clean workspace.
		d.Text = source[:strings.Index(source, "fn broken")]
		result = analyze(d, map[string]document{d.URI: d})
		edit, err := rename(result, d, declaration, "value")
		if err != nil {
			t.Fatal(err)
		}
		if len(edit.(map[string]any)["documentChanges"].([]any)[0].(map[string]any)["edits"].([]any)) != 2 {
			t.Fatal("incorrect parameter rename", edit)
		}
	}
}

func TestLibraryProjectOverlaysAndManifestChanges(t *testing.T) {
	root := t.TempDir()
	src := filepath.Join(root, "src")
	if err := os.Mkdir(src, 0700); err != nil {
		t.Fatal(err)
	}
	manifest := filepath.Join(root, "ms.toml")
	configuration := "[project]\nname = \"library\"\nsource = \"src\"\n[aliases]\n\"@lib\" = \"src\"\n"
	if err := os.WriteFile(manifest, []byte(configuration), 0600); err != nil {
		t.Fatal(err)
	}
	d := document{URI: fileURI(filepath.Join(src, "value.ms")), Text: "export fn value() -> Int: return 3\n", Version: 1}
	bad := document{URI: fileURI(filepath.Join(src, "unimported.ms")), Text: "export fn other() -> Int: return \"bad\"\n", Version: 1}
	outside := document{URI: fileURI(filepath.Join(t.TempDir(), "outside.ms")), Text: "invalid source!", Version: 1}
	docs := map[string]document{d.URI: d, bad.URI: bad, outside.URI: outside}
	result := analyze(d, docs)
	if len(result.Diagnostics) != 1 || result.Diagnostics[0].Position.File != "src/unimported.ms" || module(result, d) == nil {
		t.Fatal("library overlay discovery:", result.Diagnostics)
	}
	bad.Text = "import value from \"@lib/value.ms\"\nexport fn other() -> Int: return value()\n"
	bad.Version++
	docs[bad.URI] = bad
	result = analyze(d, docs)
	if !result.Success() || module(result, bad) == nil || navigation(result, bad, position{1, 33}, "textDocument/definition") == nil {
		t.Fatal("library overlays/navigation:", result.Diagnostics)
	}
	if err := os.WriteFile(manifest, []byte(configuration+"\"@std\" = \"src\"\n"), 0600); err != nil {
		t.Fatal(err)
	}
	result = analyze(d, docs)
	if len(result.Diagnostics) != 1 || result.Diagnostics[0].Position.File != "ms.toml" || result.Diagnostics[0].Position.Line != 6 || result.Diagnostics[0].Position.Column != 1 {
		t.Fatal("manifest edit did not refresh positioned error:", result.Diagnostics)
	}
	if err := os.WriteFile(manifest, []byte(configuration), 0600); err != nil {
		t.Fatal(err)
	}
	if result = analyze(d, docs); !result.Success() {
		t.Fatal("manifest restoration stale:", result.Diagnostics)
	}
	for _, path := range []string{filename(d.URI), filename(bad.URI)} {
		if _, err := os.Stat(path); !os.IsNotExist(err) {
			t.Fatal("overlay was written:", err)
		}
	}
}
