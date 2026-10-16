package lsp

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func signatureSource(t *testing.T, source string) map[string]any {
	t.Helper()
	cursor := strings.IndexByte(source, '|')
	source = source[:cursor] + source[cursor+1:]
	d := document{"file:///tmp/signature.ms", source, 1}
	result, err := signatureHelp(d, map[string]document{d.URI: d}, Position(source, cursor))
	if err != nil || result == nil {
		t.Fatalf("%v: %v", result, err)
	}
	return result.(map[string]any)
}
func TestSignatureHelpIncompleteNamedCalls(t *testing.T) {
	source := "# Add two numbers.\nfn sum(left: Int, right: Int) -> Int:\n    return left + right\nfn answer() -> Int:\n    return sum(left: 1, ri|\n"
	result := signatureSource(t, source)
	if result["activeParameter"] != 1 {
		t.Fatal(result)
	}
	signature := result["signatures"].([]any)[0].(map[string]any)
	if signature["label"] != "sum(left: Int, right: Int) -> Int" || signature["documentation"] == nil {
		t.Fatal(signature)
	}
	generic := signatureSource(t, "fn work(values: List[String]) -> Unit:\n    values.append(value: |\n")
	if !strings.Contains(generic["signatures"].([]any)[0].(map[string]any)["label"].(string), "String") {
		t.Fatal(generic)
	}
}
func TestIncrementalUTF16Synchronization(t *testing.T) {
	uri := "file:///tmp/incremental.ms"
	source := "# 😀 comment\nfn answer(input: Int) -> Int:\n    return input\n"
	input := frame("textDocument/didOpen", nil, map[string]any{"textDocument": document{uri, source, 1}}) + frame("textDocument/didChange", nil, map[string]any{"textDocument": document{URI: uri, Version: 2}, "contentChanges": []any{map[string]any{"range": span{position{0, 2}, position{0, 4}}, "text": "é"}, map[string]any{"range": span{position{2, 11}, position{2, 16}}, "text": "inp"}}}) + frame("textDocument/completion", 7, map[string]any{"textDocument": document{URI: uri}, "position": position{2, 14}}) + frame("shutdown", 8, nil) + frame("exit", nil, nil)
	var output bytes.Buffer
	if err := Serve(strings.NewReader(input), &output); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(output.String(), "\"label\":\"input\"") {
		t.Fatal(output.String())
	}
}
func TestProjectRenameUpdatesImportsLabelsAndAssignments(t *testing.T) {
	root := t.TempDir()
	manifest := "[project]\nname = \"editor\"\nsource = \"./src\"\nentry = \"./src/main.ms\"\n"
	os.Mkdir(filepath.Join(root, "src"), 0700)
	os.WriteFile(filepath.Join(root, "ms.toml"), []byte(manifest), 0600)
	helper := filepath.Join(root, "src/helper.ms")
	main := filepath.Join(root, "src/main.ms")
	original := "export fn add(value: Int) -> Int:\n    var current = value\n    current = current + 1\n    return current\n"
	caller := "import add from \"./helper.ms\"\nfn result() -> Int:\n    return add(value: 1)\n"
	os.WriteFile(helper, []byte(original), 0600)
	os.WriteFile(main, []byte(caller), 0600)
	d := document{fileURI(helper), original, 3}
	docs := map[string]document{d.URI: d}
	result := workspaceAnalysis(d, docs)
	renamed, err := rename(result, d, position{0, 11}, "increase", docs)
	if err != nil {
		t.Fatal(err)
	}
	changes := renamed.(map[string]any)["documentChanges"].([]any)
	if len(changes) != 2 {
		t.Fatal(renamed)
	}
	data, _ := json.Marshal(renamed)
	if !bytes.Contains(data, []byte("\"version\":null")) {
		t.Fatal(string(data))
	}
	parameter, err := rename(result, d, position{0, 15}, "input", docs)
	if err != nil {
		t.Fatal(err)
	}
	if len(parameter.(map[string]any)["documentChanges"].([]any)) != 2 {
		t.Fatal(parameter)
	}
	local, err := rename(result, d, position{1, 10}, "counter", docs)
	if err != nil {
		t.Fatal(err)
	}
	edits := local.(map[string]any)["documentChanges"].([]any)[0].(map[string]any)["edits"].([]any)
	if len(edits) != 4 {
		t.Fatal(local)
	}
	disk, _ := os.ReadFile(helper)
	if string(disk) != original {
		t.Fatal("rename mutated source")
	}
}
func TestWorkspaceAutoImportAndSymbolSearch(t *testing.T) {
	root := t.TempDir()
	os.WriteFile(filepath.Join(root, "math.ms"), []byte("export fn multiply(value: Int) -> Int:\n    return value\nfn private() -> Int:\n    return 0\n"), 0600)
	d := document{fileURI(filepath.Join(root, "main.ms")), "fn answer() -> Int:\n    return mul\n", 1}
	items, err := completionAt(d, map[string]document{d.URI: d}, position{1, 14}, true)
	if err != nil {
		t.Fatal(err)
	}
	item := itemNamed(items, "multiply")
	if item == nil || len(item.AdditionalTextEdits) != 1 {
		t.Fatal(items)
	}
	if itemNamed(items, "private") != nil {
		t.Fatal("private export leaked")
	}
	symbols := workspaceSymbols(map[string]document{d.URI: d}, nil, "multiply")
	if len(symbols) != 1 {
		t.Fatal(symbols)
	}
}

func TestSourceContractsFieldsAndTypeRename(t *testing.T) {
	source := "interface Reader:\n    fn read() -> String\ntype Box:\n    label: String\nimpl Reader for Box:\n    fn read() -> String:\n        return self.label\nfn message(value: Reader) -> String:\n    return value.read()\nfn make() -> Box:\n    return Box(label: \"value\")\n"
	root := t.TempDir()
	file := filepath.Join(root, "main.ms")
	os.WriteFile(file, []byte(source), 0600)
	d := document{fileURI(file), source, 1}
	docs := map[string]document{d.URI: d}
	checked := workspaceAnalysis(d, docs)
	if !checked.Success() {
		t.Fatal(checked.Diagnostics)
	}
	for _, tt := range []struct {
		position position
		name     string
		count    int
	}{{position{1, 8}, "fetch", 3}, {position{3, 7}, "text", 3}, {position{2, 6}, "Container", 4}} {
		renamed, err := rename(checked, d, tt.position, tt.name, docs)
		if err != nil {
			t.Fatal(tt, err)
		}
		changes := renamed.(map[string]any)["documentChanges"].([]any)
		edits := changes[0].(map[string]any)["edits"].([]any)
		if len(edits) != tt.count {
			t.Fatal(tt, renamed)
		}
	}
}
func TestSymbolRangesAndInferredTypeHints(t *testing.T) {
	source := "fn answer() -> Int:\n    let number = 42\n    return number\nfn later() -> Int:\n    return 2\n"
	d := document{"file:///tmp/symbols.ms", source, 1}
	checked := analyze(d, map[string]document{d.URI: d})
	symbols := documentSymbols(checked, d)
	first := symbols[0].(map[string]any)
	r := first["range"].(span)
	if r.End.Line != 2 || first["selectionRange"].(span).Start.Character != 3 {
		t.Fatal(first)
	}
	hints := inlayHints(checked, d, span{position{}, Position(source, len(source))})
	if len(hints) != 1 || hints[0].(map[string]any)["label"] != ": Int" {
		t.Fatal(hints)
	}
}
func TestCodeActionFilteringAndUnusedImportFix(t *testing.T) {
	source := "import ListBuilder from \"@std/collections.ms\"\nfn answer() -> Int:\n    return 42\n"
	d := document{"file:///tmp/actions.ms", source, 6}
	checked := analyze(d, map[string]document{d.URI: d})
	actions := editorActions(d, checked, span{position{}, Position(source, len(source))}, []string{"quickfix"})
	if len(actions) != 1 {
		t.Fatal(actions)
	}
	action := actions[0].(map[string]any)
	if action["title"] != "Remove unused import" {
		t.Fatal(action)
	}
	change := action["edit"].(map[string]any)["documentChanges"].([]any)[0].(map[string]any)
	if change["textDocument"].(map[string]any)["version"] != 6 {
		t.Fatal(change)
	}
}

func TestWildcardBindingsRemainSafeAcrossEditorFeatures(t *testing.T) {
	source := "fn answer(value: Optional[Int]) -> Int:\n    match value:\n        some(_):\n            return 1\n        none:\n            return 0\n"
	d := document{"file:///tmp/wildcard.ms", source, 1}
	docs := map[string]document{d.URI: d}
	checked := workspaceAnalysis(d, docs)
	if !checked.Success() {
		t.Fatal(checked.Diagnostics)
	}
	found := false
	for _, entry := range sourceIndex(checked) {
		if entry.name == "_" {
			t.Fatal("wildcard became a renameable symbol")
		}
		if entry.name == "value" {
			found = true
		}
	}
	if !found {
		t.Fatal("parameter references missing")
	}
	if len(semantic(d, checked)["data"].([]int)) == 0 {
		t.Fatal("semantic tokens missing")
	}
}

func TestStandardLibraryNavigationUsesCompilerSources(t *testing.T) {
	source := "fn count(values: List[String]) -> Int:\n    return values.length\n"
	d := document{"file:///tmp/standard-navigation.ms", source, 1}
	docs := map[string]document{d.URI: d}
	standardURI := "manuscript-stdlib:///collections.ms"
	standardSource, err := standardLibrarySource(standardURI)
	if err != nil {
		t.Fatal(err)
	}
	docs[standardURI] = document{standardURI, standardSource, 1}
	checked := analyze(d, docs)
	if !checked.Success() {
		t.Fatal(checked.Diagnostics)
	}
	for _, pos := range []position{{0, 18}, {1, 20}} {
		locations := navigation(checked, d, pos, "textDocument/definition")
		if locations == nil {
			t.Fatalf("missing standard definition at %v", pos)
		}
		location := locations.([]any)[0].(map[string]any)
		uri := location["uri"].(string)
		if uri != "manuscript-stdlib:///collections.ms" {
			t.Fatal(location)
		}
		content, err := standardLibrarySource(uri)
		if err != nil || !strings.Contains(content, "export type List") {
			t.Fatal(content, err)
		}
		if _, err := rename(checked, d, pos, "Changed", docs); err == nil {
			t.Fatal("allowed standard-library rename")
		}
	}
	for _, uri := range []string{"file:///etc/passwd", "manuscript-stdlib:/../collections.ms", "manuscript-stdlib://host/collections.ms", "manuscript-stdlib:/missing.ms"} {
		if _, err := standardLibrarySource(uri); err == nil {
			t.Fatalf("accepted %s", uri)
		}
	}
}

func TestBytesValuesHoverIncludesOperationContract(t *testing.T) {
	source := `import Bytes from "@std/bytes.ms"
fn extract(data: Bytes) -> List[Int]:
    let bound: fn() -> List[Int] = data.values
    return data.values()
`
	d := document{"file:///tmp/bytes-values-hover.ms", source, 1}
	checked := analyze(d, map[string]document{d.URI: d})
	if !checked.Success() {
		t.Fatal(checked.Diagnostics)
	}
	for _, offset := range []int{strings.Index(source, "values\n"), strings.Index(source, "values()")} {
		hover := navigation(checked, d, Position(source, offset), "textDocument/hover")
		if hover == nil {
			t.Fatal("missing Bytes.values hover")
		}
		text := hover.(map[string]any)["contents"].(map[string]any)["value"].(string)
		if !strings.Contains(text, "fn()->List[Int]") || !strings.Contains(text, "fresh mutable list") || !strings.Contains(text, "leaves the Bytes unchanged") {
			t.Fatalf("operation contract missing: %s", text)
		}
	}
}

func TestBytesConstructorRetainsValuesSignature(t *testing.T) {
	for _, call := range []string{"Bytes(|", "Bytes(values: |"} {
		source := "import Bytes from \"@std/bytes.ms\"\nfn make() -> Bytes:\n    return " + call + "\n"
		result := signatureSource(t, source)
		signature := result["signatures"].([]any)[0].(map[string]any)
		if signature["label"] != "Bytes(values: List[Int]) -> Bytes" {
			t.Fatalf("%s: constructor argument lost with field removal: %v", call, signature)
		}
	}
}

func TestNavigationWithinStandardLibrary(t *testing.T) {
	for _, item := range []struct{ file, needle, target, name string }{
		{"collections.ms", "Result[List[T]", "result.ms", "Result"},
		{"collections.ms", "Optional[T]", "optional.ms", "Optional"},
		{"collections.ms", "List[T]) ->", "collections.ms", "List"},
		{"cli.ms", "List[String]", "collections.ms", "List"},
	} {
		t.Run(item.file+"/"+item.needle, func(t *testing.T) {
			uri := "manuscript-stdlib:///" + item.file
			source, err := standardLibrarySource(uri)
			if err != nil {
				t.Fatal(err)
			}
			d := document{uri, source, 1}
			docs := map[string]document{uri: d}
			checked := analyze(d, docs)
			if !checked.Success() || module(checked, d) == nil {
				t.Fatal("standard document was not resolved", checked.Diagnostics)
			}
			// Guide comments may repeat signatures. Navigate the declaration,
			// rather than selecting a prose occurrence at the end of the file.
			offset, base := -1, 0
			for _, line := range strings.SplitAfter(source, "\n") {
				if !strings.HasPrefix(strings.TrimSpace(line), "#") {
					if at := strings.LastIndex(line, item.needle); at >= 0 {
						offset = base + at
					}
				}
				base += len(line)
			}
			if offset < 0 {
				t.Fatal("missing source reference")
			}
			pos := Position(source, offset)
			for _, method := range []string{"textDocument/definition", "textDocument/typeDefinition"} {
				locations := navigation(checked, d, pos, method)
				if method == "textDocument/typeDefinition" {
					locations = typeDefinition(checked, d, pos)
				}
				if locations == nil {
					t.Fatalf("missing %s", method)
				}
				location := locations.([]any)[0].(map[string]any)
				if location["uri"] != "manuscript-stdlib:///"+item.target {
					t.Fatal(location)
				}
				target, err := standardLibrarySource(location["uri"].(string))
				if err != nil {
					t.Fatal(err)
				}
				line := location["range"].(span).Start.Line
				header := strings.Split(target, "\n")[line]
				if !strings.Contains(header, "type "+item.name) && !strings.Contains(header, "interface "+item.name) {
					t.Fatalf("wrong definition: %v", location)
				}
			}
			if hover := navigation(checked, d, pos, "textDocument/hover"); hover == nil {
				t.Fatal("missing hover in standard document")
			}
			if _, err := rename(checked, d, pos, "Changed", docs); err == nil {
				t.Fatal("allowed standard-library rename")
			}
		})
	}
}

func TestGroupedImportFixKeepsUsedBindingAndRenameUsesNameOffsets(t *testing.T) {
	root := t.TempDir()
	helper := filepath.Join(root, "helper.ms")
	source := "import { first, second } from \"./helper.ms\"\nfn answer() -> Int:\n    return first()\n"
	os.WriteFile(helper, []byte("export fn first() -> Int:\n    return 1\nexport fn second() -> Int:\n    return 2\n"), 0600)
	file := filepath.Join(root, "main.ms")
	os.WriteFile(file, []byte(source), 0600)
	d := document{fileURI(file), source, 1}
	docs := map[string]document{d.URI: d}
	checked := analyze(d, docs)
	if !checked.Success() {
		t.Fatal(checked.Diagnostics)
	}
	actions := editorActions(d, checked, span{position{}, Position(source, len(source))}, []string{"quickfix"})
	if len(actions) != 1 {
		t.Fatal(actions)
	}
	raw := actions[0].(map[string]any)["edit"].(map[string]any)["documentChanges"].([]any)[0].(map[string]any)["edits"].([]any)
	fixed := source
	for _, entry := range raw {
		edit := entry.(map[string]any)
		r := edit["range"].(span)
		start, _ := Offset(fixed, r.Start)
		end, _ := Offset(fixed, r.End)
		fixed = fixed[:start] + edit["newText"].(string) + fixed[end:]
	}
	updated := d
	updated.Text = fixed
	if !analyze(updated, map[string]document{d.URI: updated}).Success() || !strings.Contains(fixed, "first") || strings.Contains(fixed, "second") {
		t.Fatal(fixed)
	}
	named, err := rename(checked, d, Position(source, strings.Index(source, "first")), "primary", docs)
	if err != nil || named == nil {
		t.Fatal(named, err)
	}
	locations := navigation(checked, d, Position(source, strings.Index(source, "second")), "textDocument/definition")
	if locations == nil || locations.([]any)[0].(map[string]any)["uri"] != fileURI(helper) {
		t.Fatal(locations)
	}
}

func TestBareArgumentRenameAddsNoLabels(t *testing.T) {
	source := "fn subtract(amount: Int, deduction: Int) -> Int: return amount - deduction\nfn call() -> Int:\n    let amount = 10\n    let deduction = 3\n    return subtract(deduction, amount)\n"
	d := document{fileURI(filepath.Join(t.TempDir(), "shorthand.ms")), source, 1}
	docs := map[string]document{d.URI: d}
	result := analyze(d, docs)
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	for _, tc := range []struct {
		pos  position
		name string
	}{
		{position{2, 9}, "total"},
		{position{0, 13}, "total"},
	} {
		edit, err := rename(result, d, tc.pos, tc.name, docs)
		if err != nil {
			t.Fatal(err)
		}
		data, _ := json.Marshal(edit)
		if strings.Contains(string(data), ": ") && strings.Contains(string(data), `"newText":"`+tc.name+`:`) || strings.Contains(string(data), `: `+tc.name) {
			t.Fatalf("rename added a label: %s", data)
		}
	}
}

func TestPreferredNativeNamesHoverAndNavigation(t *testing.T) {
	for _, tc := range []struct{ name, receiver, contract, module string }{
		{"set", "List[Int]", "Replaces an element in place", "collections.ms"},
		{"splice", "List[Int]", "mutating and returning this List", "collections.ms"},
		{"remove", "Map[Int, Int]", "remaining entries retain insertion order", "collections.ms"},
		{"reverse_in_place", "List[Int]", "Reverses this list in place", "collections.ms"},
		{"reversed", "List[Int]", "independent outer storage", "collections.ms"},
		{"reversed", "Bytes", "reversed copy", "bytes.ms"},
		{"remove", "List[Int]", "Removes an element in place", "collections.ms"},
		{"add", "Set[Int]", "Adds a value in place", "collections.ms"},
		{"remove", "Set[Int]", "Removes an equal value in place", "collections.ms"},
		{"replace_first", "String", "an explicit cap can replace more", "intrinsics.ms"},
		{"replace_n", "String", "count limits replacements", "intrinsics.ms"},
		{"replace_all", "Regex", "literal replacement text", "regex.ms"},
	} {
		t.Run(tc.receiver+"/"+tc.name, func(t *testing.T) {
			source := "import Bytes from \"@std/bytes.ms\"\nimport Regex from \"@std/regex.ms\"\nfn check(receiver: " + tc.receiver + ") -> Unit:\n    let bound = receiver." + tc.name + "\n"
			d := document{"file:///tmp/preferred-names-hover.ms", source, 1}
			checked := analyze(d, map[string]document{d.URI: d})
			if !checked.Success() {
				t.Fatal(checked.Diagnostics)
			}
			pos := Position(source, strings.LastIndex(source, tc.name))
			hover := navigation(checked, d, pos, "textDocument/hover")
			if hover == nil {
				t.Fatal("missing hover")
			}
			text := hover.(map[string]any)["contents"].(map[string]any)["value"].(string)
			if !strings.Contains(text, tc.contract) {
				t.Fatalf("missing contract: %s", text)
			}
			target := navigation(checked, d, pos, "textDocument/definition")
			if target == nil {
				t.Fatal("missing definition")
			}
			location := target.([]any)[0].(map[string]any)
			if location["uri"] != "manuscript-stdlib:///"+tc.module {
				t.Fatal(location)
			}
		})
	}
}

func TestIncrementalEditsClampOutOfRangePositions(t *testing.T) {
	uri := "file:///tmp/clamp.ms"
	source := "fn answer() -> Int:\n    return 42\n"
	// Positions past the end of a line or of the document clamp, so the
	// server's copy keeps matching the editor's.
	edits := []any{
		map[string]any{"range": span{position{1, 100}, position{1, 100}}, "text": " + 1"},
		map[string]any{"range": span{position{99, 0}, position{99, 0}}, "text": "# end\n"},
	}
	input := frame("textDocument/didOpen", nil, map[string]any{"textDocument": document{uri, source, 1}}) + frame("textDocument/didChange", nil, map[string]any{"textDocument": document{URI: uri, Version: 2}, "contentChanges": edits}) + frame("textDocument/formatting", 3, map[string]any{"textDocument": document{URI: uri}}) + frame("shutdown", 4, nil) + frame("exit", nil, nil)
	var output bytes.Buffer
	if err := Serve(strings.NewReader(input), &output); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(output.String(), "return 42 + 1") || !strings.Contains(output.String(), "# end") {
		t.Fatal(output.String())
	}
}
