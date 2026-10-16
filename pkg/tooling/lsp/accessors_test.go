package lsp

import (
	"strings"
	"testing"
)

const accessorEditorSource = `interface Sized:
    # The current count in items.
    get length -> Int
    fn inspect() -> Int
type Buffer:
    count: Int
impl Sized for Buffer:
    get length -> Int:
        return self.count
    fn inspect() -> Int:
        return self.count
fn size[T: Sized](value: T) -> Int:
    return value.length
fn use(value: Buffer) -> Int:
    let view = Sized(value)
    return value.length + view.length
`

func TestAccessorCompletionOffersReadOnlyValue(t *testing.T) {
	for _, source := range []string{
		accessorEditorSource + "fn complete(value: Buffer) -> Int:\n    return value.le|\n",
		accessorEditorSource + "fn complete[T: Sized](value: T) -> Int:\n    return value.le|\n",
		"fn complete(value: List[Int]) -> Int:\n    return value.le|\n",
		"fn complete(value: Int) -> Unit:\n    let duration = value.se|\n",
	} {
		items := completeSource(t, source)
		name, typ := "length", "Int"
		if strings.Contains(source, "value.se|") {
			name, typ = "seconds", "Duration"
		}
		item := itemNamed(items, name)
		if item == nil || item.Kind != 10 || item.Detail != typ || item.TextEdit.(map[string]any)["newText"] != name || item.InsertTextFormat != 1 {
			t.Fatalf("accessor must offer its value without call syntax: %+v", item)
		}
	}
	items := completeSource(t, "fn describe(value: Error) -> String:\n    return value.mes|\n")
	message := itemNamed(items, "message")
	if message == nil || message.Kind != 2 || message.Detail != "fn()->String" || !strings.Contains(message.TextEdit.(map[string]any)["newText"].(string), "message(") {
		t.Fatalf("Error.message must remain a callable completion: %+v", message)
	}
}

func TestAccessorNavigationRenameAndSemanticTokens(t *testing.T) {
	for _, newline := range []string{"\n", "\r\n"} {
		source := strings.ReplaceAll(accessorEditorSource, "\n", newline)
		d := document{"file:///tmp/accessor-navigation.ms", source, 7}
		docs := map[string]document{d.URI: d}
		result := analyze(d, docs)
		if !result.Success() {
			t.Fatal(result.Diagnostics)
		}
		pos := Position(source, strings.LastIndex(source, "value.length")+len("value."))
		hover := navigation(result, d, pos, "textDocument/hover").(map[string]any)["contents"].(map[string]any)["value"].(string)
		if !strings.Contains(hover, "get length -> Int") || strings.Contains(hover, "fn()->Int") {
			t.Fatal("hover leaked implementation callable type", hover)
		}
		definition := navigation(result, d, pos, "textDocument/definition")
		if definition == nil || definition.([]any)[0].(map[string]any)["range"].(span).Start.Line != 7 {
			t.Fatal("concrete accessor must navigate to selected implementation", definition)
		}
		renameResult, err := rename(result, d, pos, "item_count", docs)
		if err != nil {
			t.Fatal(err)
		}
		changes := renameResult.(map[string]any)["documentChanges"].([]any)
		if len(changes) != 1 || len(changes[0].(map[string]any)["edits"].([]any)) != 5 {
			t.Fatalf("rename must include contract, implementation, concrete, view and generic uses: %+v", changes)
		}
		data := semantic(d, result)["data"].([]int)
		line, character, propertyCount := 0, 0, 0
		for i := 0; i < len(data); i += 5 {
			if data[i] != 0 {
				character = 0
			}
			line += data[i]
			character += data[i+1]
			start, err := Offset(source, position{line, character})
			if err != nil {
				t.Fatal(err)
			}
			if strings.HasPrefix(source[start:], "length") && data[i+3] == 7 {
				propertyCount++
			}
		}
		if propertyCount != 5 {
			t.Fatalf("accessor declarations/reads must be property tokens: %d", propertyCount)
		}
	}
}

func TestStandardAccessorNavigationAndErrorMethodMetadata(t *testing.T) {
	source := "fn count(values: List[Int]) -> Int:\n    return values.length\n"
	file, definition, hover := definitionAt(t, source, strings.Index(source, ".length")+1)
	if file != "@std/collections.ms" || !strings.Contains(definition, "length -> Int") || !strings.Contains(hover, "get length -> Int") {
		t.Fatalf("standard accessor: %s %q %q", file, definition, hover)
	}
	source = "fn describe(value: Error) -> String:\n    let bound: fn() -> String = value.message\n    return bound()\n"
	file, definition, hover = definitionAt(t, source, strings.Index(source, ".message")+1)
	if file != "@std/errors.ms" || !strings.Contains(definition, "message() -> String") || !strings.Contains(hover, "fn()->String") {
		t.Fatalf("Error.message must remain a method: %s %q %q", file, definition, hover)
	}
}

func TestIncompleteAccessorPreservesFollowingEditorDeclaration(t *testing.T) {
	const input = `interface Sized:
    get length ->
    fn inspect() -> Int
fn stable(value: Int) -> Int:
    let label = "🦊"
    return value
`
	for _, newline := range []string{"\n", "\r\n"} {
		source := strings.ReplaceAll(input, "\n", newline)
		d := document{"file:///tmp/incomplete-accessor.ms", source, 1}
		result := analyze(d, map[string]document{d.URI: d})
		if result.Program == nil || len(result.Diagnostics) == 0 {
			t.Fatal("expected an incomplete snapshot with retained declarations", result.Diagnostics)
		}
		pos := Position(source, strings.LastIndex(source, "value"))
		location := navigation(result, d, pos, "textDocument/definition")
		if location == nil || location.([]any)[0].(map[string]any)["range"].(span).Start != (position{3, 10}) {
			t.Fatal("incomplete accessor erased or shifted the following parameter", location)
		}
	}
}

func TestAccessorNavigationAfterUnicodeUsesUTF16Positions(t *testing.T) {
	for _, newline := range []string{"\n", "\r\n"} {
		source := strings.ReplaceAll(accessorEditorSource+"fn unicode(value: Buffer) -> String:\n    return \"🦊{value.length}\"\n", "\n", newline)
		d := document{"file:///tmp/unicode-accessor.ms", source, 1}
		result := analyze(d, map[string]document{d.URI: d})
		if !result.Success() {
			t.Fatal(result.Diagnostics)
		}
		pos := Position(source, strings.LastIndex(source, ".length")+1)
		location := navigation(result, d, pos, "textDocument/definition")
		if location == nil || location.([]any)[0].(map[string]any)["range"].(span).Start.Line != 7 {
			t.Fatal("Unicode before an accessor shifted navigation", location)
		}
	}
}
