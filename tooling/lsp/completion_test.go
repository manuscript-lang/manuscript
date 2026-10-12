package lsp

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLocalExtensionCompletionAndNavigation(t *testing.T) {
	root := t.TempDir()
	sources := map[string]string{
		"domain.ms": "export type Box:\n    value: Int\n",
		"extension.ms": `import Box from "./domain.ms"
interface Read:
    fn get() -> Int
impl Read for Box:
    fn get() -> Int:
        return self.value
export fn read(value: Box) -> Int:
    return value.get()
`,
		"main.ms": `import Box from "./domain.ms"
import read from "./extension.ms"
fn use(value: Box) -> Int:
    return value.value
`,
	}
	for name, source := range sources {
		if err := os.WriteFile(filepath.Join(root, name), []byte(source), 0600); err != nil {
			t.Fatal(err)
		}
	}
	for _, name := range []string{"extension.ms", "main.ms"} {
		source := sources[name]
		at := strings.LastIndex(source, "value.") + len("value.")
		d := document{fileURI(filepath.Join(root, name)), source, 1}
		items, err := completionAt(d, map[string]document{d.URI: d}, Position(source, at), true)
		if err != nil {
			t.Fatal(err)
		}
		if (itemNamed(items, "get") != nil) != (name == "extension.ms") {
			t.Fatalf("extension visibility in %s: %+v", name, items)
		}
		if name == "extension.ms" {
			result := analyze(d, map[string]document{d.URI: d})
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
			definition := navigation(result, d, Position(source, at), "textDocument/definition")
			if definition == nil {
				t.Fatal("missing extension method definition")
			}
			location := definition.([]any)[0].(map[string]any)
			if location["uri"] != d.URI || location["range"].(span).Start.Line != 4 {
				t.Fatalf("wrong extension definition: %v", definition)
			}
		}
	}
}

func completeSource(t *testing.T, source string) []completionItem {
	t.Helper()
	at := strings.IndexByte(source, '|')
	if at < 0 {
		t.Fatal("missing cursor")
	}
	source = source[:at] + source[at+1:]
	d := document{"file:///tmp/completion.ms", source, 1}
	items, err := completionAt(d, map[string]document{d.URI: d}, Position(source, at), true)
	if err != nil {
		t.Fatal(err)
	}
	return items
}
func itemNamed(items []completionItem, name string) *completionItem {
	for i := range items {
		if items[i].Label == name {
			return &items[i]
		}
	}
	return nil
}
func TestTypedCompletionWhileEditing(t *testing.T) {
	tests := []struct {
		name, source string
		want, absent []string
	}{
		{"parameter", "fn answer(input: Int) -> Int:\n    return inp|\n", []string{"input"}, nil},
		{"locals before cursor", "fn answer() -> Int:\n    let before = 1\n    be|\n    let behind = 2\n    return before\n", []string{"before"}, []string{"behind"}},
		{"siblings hidden", "fn answer() -> Int:\n    if true:\n        let secret = 1\n    sec|\n    return 0\n", nil, []string{"secret"}},
		{"list methods", "import List from \"@std/collections.ms\"\nfn count(items: List[Int]) -> Int:\n    return items.|\n", []string{"length", "get", "append", "concat"}, []string{"byte_length", "send"}},
		{"member prefix", "fn size(text: String) -> Int:\n    return text.byte_|\n", []string{"byte_length"}, []string{"parse_int"}},
		{"record fields", "type Point:\n    x: Int\n    y: String\nfn read(point: Point) -> Int:\n    return point.|\n", []string{"x", "y"}, []string{"length"}},
		{"native opaque fields", "import Queue from \"@std/queues.ms\"\nfn read(queue: Queue[Int]) -> Unit:\n    queue.|\n", []string{"enqueue", "dequeue", "peek", "length", "is_empty"}, []string{"capacity", "send", "receive", "close"}},
		{"named arguments incomplete call", "fn sum(left: Int, right: Int) -> Int:\n    return left + right\nfn answer() -> Int:\n    return sum(le|\n", []string{"left"}, []string{"right"}},
		{"used arguments omitted", "fn sum(left: Int, right: Int) -> Int:\n    return left + right\nfn answer() -> Int:\n    return sum(left: 1, |\n", []string{"right"}, []string{"left"}},
		{"typed argument expression", "fn sum(left: Int, right: Int) -> Int:\n    return left + right\nfn answer(input: Int) -> Int:\n    return sum(left: inp|\n", []string{"input"}, nil},
		{"auto import", "fn work() -> Unit:\n    Que|\n", []string{"Queue"}, nil},
		{"comments", "fn work() -> Unit:\n    # Que|\n    unit\n", nil, []string{"Queue"}},
		{"strings", "fn work() -> String:\n    return \"Que|\"\n", nil, []string{"Queue"}},
		{"generic alternative", "import Optional from \"@std/optional.ms\"\nfn work() -> Optional[Int]:\n    return Optional[Int].|\n", []string{"some", "none"}, nil},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			items := completeSource(t, tt.source)
			for _, want := range tt.want {
				if itemNamed(items, want) == nil {
					t.Fatalf("missing %s: %+v", want, items)
				}
			}
			for _, absent := range tt.absent {
				if itemNamed(items, absent) != nil {
					t.Fatalf("leaked %s: %+v", absent, items)
				}
			}
		})
	}
}
func TestCompletionSnippetsEditsAndSpecialization(t *testing.T) {
	items := completeSource(t, "import List from \"@std/collections.ms\"\nfn count(items: List[String]) -> Unit:\n    items.ap|\n")
	item := itemNamed(items, "append")
	if item == nil {
		t.Fatal(items)
	}
	if !strings.Contains(item.Detail, "String") || item.InsertTextFormat != 2 {
		t.Fatal(item)
	}
	edit := item.TextEdit.(map[string]any)
	if edit["newText"] != "append(value: ${1:value})$0" {
		t.Fatal(edit)
	}
	if got := edit["range"].(span); got.Start != (position{2, 10}) || got.End != (position{2, 12}) {
		t.Fatal(got)
	}
	imports := completeSource(t, "fn work() -> Unit:\n    Que|\n")
	queue := itemNamed(imports, "Queue")
	if queue == nil || len(queue.AdditionalTextEdits) != 1 {
		t.Fatal(queue)
	}
}
func TestCompletionSurvivesIndependentSyntaxErrors(t *testing.T) {
	items := completeSource(t, "fn answer(input: Int) -> Int:\n    return inp|\nfn broken(\n")
	if itemNamed(items, "input") == nil {
		t.Fatal(items)
	}
	items = completeSource(t, "import Missing from \"./absent.ms\"\nfn answer(input: Int) -> Int:\n    return inp|\n")
	if itemNamed(items, "input") == nil {
		t.Fatal(items)
	}
}
func TestShadowingCompletionUsesNearestType(t *testing.T) {
	items := completeSource(t, "fn answer(input: Int) -> Unit:\n    if true:\n        let input = \"text\"\n        inp|\n    return unit\n")
	item := itemNamed(items, "input")
	if item == nil || item.Detail != "String" {
		t.Fatal(item, items)
	}
}
func TestGenericBoundMembers(t *testing.T) {
	items := completeSource(t, "interface Reader:\n    fn read() -> String\nfn answer[T: Reader](reader: T) -> String:\n    return reader.|\n")
	if itemNamed(items, "read") == nil {
		t.Fatal(items)
	}
}

func TestUniversalToStringCompletion(t *testing.T) {
	for _, source := range []string{
		"fn text(value: Bool) -> String:\n    return value.|\n",
		"fn text[T](value: T) -> String:\n    return value.|\n",
		"interface Named:\n    fn name() -> String\nfn text(value: Named) -> String:\n    return value.|\n",
		"type Item:\n    value: Int\nfn text(value: Item) -> String:\n    return value.|\n",
		"fn text(value: fn() -> Int) -> String:\n    return value.|\n",
		"import Queue from \"@std/queues.ms\"\nfn text(value: Queue[Int]) -> String:\n    return value.|\n",
	} {
		items := completeSource(t, source)
		item := itemNamed(items, "toString")
		if item == nil || item.Detail != "fn()->String" || item.TextEdit.(map[string]any)["newText"] != "toString()$0" {
			t.Fatalf("missing universal method for %s: %+v", source, items)
		}
	}
}
func BenchmarkMemberCompletion(b *testing.B) {
	source := "import List from \"@std/collections.ms\"\nfn answer(items: List[String]) -> Int:\n    return items.\n"
	d := document{"file:///tmp/benchmark-completion.ms", source, 1}
	docs := map[string]document{d.URI: d}
	p := position{2, 17}
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		if _, err := completionAt(d, docs, p, true); err != nil {
			b.Fatal(err)
		}
	}
}
func TestFuzzyMemberCompletion(t *testing.T) {
	items := completeSource(t, "fn size(text: String) -> Int:\n    return text.bl|\n")
	if itemNamed(items, "byte_length") == nil {
		t.Fatal(items)
	}
}

func TestExpandedStandardMembersAndInterfaceSnippet(t *testing.T) {
	items := completeSource(t, "import HttpClient from \"@std/http.ms\"\nfn work(client: HttpClient) -> Unit:\n    client.|\n")
	if itemNamed(items, "send_stream") == nil {
		t.Fatal(items)
	}
	items = completeSource(t, "inter|")
	if item := itemNamed(items, "interface"); item == nil || !strings.Contains(item.TextEdit.(map[string]any)["newText"].(string), "fn operation") {
		t.Fatal(items)
	}
}

func TestGroupedImportCompletion(t *testing.T) {
	for _, source := range []string{"import { List, Ma| } from \"@std/collections.ms\"\n", "import {\n    List,\n    Ma|,\n} from \"@std/collections.ms\"\n"} {
		items := completeSource(t, source)
		if itemNamed(items, "Map") == nil {
			t.Fatal(items)
		}
		item := itemNamed(items, "Map")
		if item.TextEdit.(map[string]any)["newText"] != "Map" || len(item.AdditionalTextEdits) != 0 {
			t.Fatal(item)
		}
	}
	items := completeSource(t, "import { List, | } from \"@std/collections.ms\"\n")
	if itemNamed(items, "List") != nil || itemNamed(items, "Map") == nil {
		t.Fatal(items)
	}
}
