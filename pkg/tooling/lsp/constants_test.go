package lsp

import (
	"strings"
	"testing"
)

const constantSource = `# max items
export let MAX_ITEMS = 100
let NAMES: List[String] = ["a"]
let LIMIT = MAX_ITEMS * 2

fn is_full(count: Int) -> Bool:
    return count >= LIMIT
fn names() -> Int:
    return NAMES.length()
`

func TestConstantHoverShowsValueType(t *testing.T) {
	for _, item := range []struct{ needle, want string }{
		{"MAX_ITEMS = ", "MAX_ITEMS: Int"},
		{"LIMIT\n", "LIMIT: Int"},
		{"NAMES.length", "NAMES: List[String]"},
		{"MAX_ITEMS *", "MAX_ITEMS: Int"},
	} {
		_, _, hover := definitionAt(t, constantSource, strings.LastIndex(constantSource, item.needle))
		if !strings.Contains(hover, item.want+"\n") {
			t.Errorf("%q: hover %q, want %q", item.needle, hover, item.want)
		}
	}
}

func TestConstantCompletionIsAValueNotACall(t *testing.T) {
	source := strings.Replace(constantSource, "count >= LIMIT", "count >= LIM", 1)
	d := document{"file:///tmp/constants.ms", source, 1}
	items, err := completionAt(d, map[string]document{d.URI: d}, Position(source, strings.Index(source, "LIM\n")+3), true)
	if err != nil {
		t.Fatal(err)
	}
	item := itemNamed(items, "LIMIT")
	if item == nil || item.Kind != 21 || item.Detail != "Int" || item.TextEdit.(map[string]any)["newText"] != "LIMIT" {
		t.Fatalf("constant completion: %+v", item)
	}
}

func TestConstantDocumentSymbolsAreConstants(t *testing.T) {
	d := document{"file:///tmp/constants.ms", constantSource, 1}
	result := analyze(d, map[string]document{d.URI: d})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	kinds := map[string]any{}
	for _, symbol := range documentSymbols(result, d) {
		entry := symbol.(map[string]any)
		kinds[entry["name"].(string)] = entry["kind"]
		if entry["name"] == "LIMIT" && entry["detail"] != "Int" {
			t.Errorf("LIMIT detail %v", entry["detail"])
		}
	}
	if kinds["MAX_ITEMS"] != 14 || kinds["NAMES"] != 14 || kinds["is_full"] != 12 {
		t.Fatalf("symbol kinds %v", kinds)
	}
}

func TestHoverSurvivesSyntaxErrorInsideCalledFunction(t *testing.T) {
	source := "fn work(a: Int) -> Int:\n    let b = a + 1\n    let c = = 3\n    return b\n\nexport fn main() -> Int:\n    return work(2)\n"
	d := document{"file:///tmp/recovered.ms", source, 1}
	checked := analyze(d, map[string]document{d.URI: d})
	if len(checked.Diagnostics) != 1 {
		t.Fatal(checked.Diagnostics)
	}
	hover, ok := navigation(checked, d, Position(source, strings.LastIndex(source, "work")), "textDocument/hover").(map[string]any)
	if !ok || !strings.Contains(hover["contents"].(map[string]any)["value"].(string), "work: fn(a: Int)->Int") {
		t.Fatalf("hover %v", hover)
	}
}
