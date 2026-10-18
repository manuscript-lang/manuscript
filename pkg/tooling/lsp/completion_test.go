package lsp

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/lexer"
)

func TestLocalExtensionCompletionAndNavigation(t *testing.T) {
	root := t.TempDir()
	sources := map[string]string{
		"domain.ms": "export type Box:\n    value: Int\n",
		"extension.ms": `import Box from "./domain.ms"
interface Read:
    fn get() Int
impl Read for Box:
    fn get() Int:
        return self.value
export fn read(value: Box) Int:
    return value.get()
`,
		"main.ms": `import Box from "./domain.ms"
import read from "./extension.ms"
fn use(value: Box) Int:
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

func TestPreludeCompletionNeedsNoImport(t *testing.T) {
	for _, name := range []string{"Optional", "Result", "Error", "List", "Map", "Set"} {
		items := completeSource(t, "fn work(value: "+name[:2]+"|) Unit:\n    return\n")
		item := itemNamed(items, name)
		if item == nil || len(item.AdditionalTextEdits) != 0 {
			t.Fatalf("%s must complete without an import: %+v", name, item)
		}
	}
}

func TestCollectionPreludeExpressionCompletionNeedsNoImport(t *testing.T) {
	for _, name := range []string{"List", "Map", "Set"} {
		items := completeSource(t, "fn work() Unit:\n    "+name[:2]+"|\n")
		item := itemNamed(items, name)
		if item == nil || len(item.AdditionalTextEdits) != 0 {
			t.Fatalf("%s: %+v", name, item)
		}
	}
}

func TestPreludeNavigationUsesStandardSource(t *testing.T) {
	source := "fn work(value: Optional[Int]) Result[Int, Error]:\n    return ok(value: value.get())\n"
	d := document{"file:///tmp/prelude.ms", source, 1}
	result := analyze(d, map[string]document{d.URI: d})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	for name, file := range map[string]string{"Optional": "optional.ms", "Result": "result.ms", "Error": "errors.ms"} {
		target := navigation(result, d, Position(source, strings.Index(source, name)), "textDocument/definition")
		if target == nil || target.([]any)[0].(map[string]any)["uri"] != "manuscript-stdlib:///"+file {
			t.Fatalf("%s did not navigate to its standard declaration: %v", name, target)
		}
	}
}

func TestTypedCompletionWhileEditing(t *testing.T) {
	tests := []struct {
		name, source string
		want, absent []string
	}{
		{"parameter", "fn answer(input: Int) Int:\n    return inp|\n", []string{"input"}, nil},
		{"locals before cursor", "fn answer() Int:\n    let before = 1\n    be|\n    let behind = 2\n    return before\n", []string{"before"}, []string{"behind"}},
		{"siblings hidden", "fn answer() Int:\n    if true:\n        let secret = 1\n    sec|\n    return 0\n", nil, []string{"secret"}},
		{"list methods", "fn count(items: List[Int]) Int:\n    return items.|\n", []string{"length", "at", "append", "concat"}, []string{"byte_length", "send"}},
		{"prelude set methods", "fn count(items: Set[Int]) Int:\n    return items.|\n", []string{"length", "contains", "add", "remove"}, []string{"at", "append", "send"}},
		{"member prefix", "fn size(text: String) Int:\n    return text.byte_|\n", []string{"byte_length"}, []string{"parse_int"}},
		{"record fields", "type Point:\n    x: Int\n    y: String\nfn read(point: Point) Int:\n    return point.|\n", []string{"x", "y"}, []string{"length"}},
		{"native opaque fields", "import Queue from \"@std/queues.ms\"\nfn read(queue: Queue[Int]) Unit:\n    queue.|\n", []string{"enqueue", "dequeue", "peek", "length", "is_empty"}, []string{"capacity", "send", "receive", "close"}},
		{"named arguments incomplete call", "fn sum(left: Int, right: Int) Int:\n    return left + right\nfn answer() Int:\n    return sum(le|\n", []string{"left"}, []string{"right"}},
		{"used arguments omitted", "fn sum(left: Int, right: Int) Int:\n    return left + right\nfn answer() Int:\n    return sum(left: 1, |\n", []string{"right"}, []string{"left"}},
		{"typed argument expression", "fn sum(left: Int, right: Int) Int:\n    return left + right\nfn answer(input: Int) Int:\n    return sum(left: inp|\n", []string{"input"}, nil},
		{"auto import", "fn work() Unit:\n    Que|\n", []string{"Queue"}, nil},
		{"comments", "fn work() Unit:\n    # Que|\n    unit\n", nil, []string{"Queue"}},
		{"strings", "fn work() String:\n    return \"Que|\"\n", nil, []string{"Queue"}},
		{"optional methods", "fn work(value: Optional[Int]) Int:\n    return value.|\n", []string{"is_some", "is_none", "get", "or_else"}, []string{"some", "none", "unwrap"}},
		{"generic alternative", "fn work() Optional[Int]:\n    return Optional[Int].|\n", []string{"some", "none"}, nil},
		{"prelude result cases", "fn work() Result[Int, Error]:\n    return Result[Int, Error].|\n", []string{"ok", "error"}, nil},
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
	items := completeSource(t, "fn count(items: List[String]) Unit:\n    items.ap|\n")
	item := itemNamed(items, "append")
	if item == nil {
		t.Fatal(items)
	}
	if !strings.Contains(item.Detail, "String") || item.InsertTextFormat != 2 {
		t.Fatal(item)
	}
	edit := item.TextEdit.(map[string]any)
	if edit["newText"] != "append(${1:value})$0" {
		t.Fatal(edit)
	}
	if got := edit["range"].(span); got.Start != (position{1, 10}) || got.End != (position{1, 12}) {
		t.Fatal(got)
	}
	imports := completeSource(t, "fn work() Unit:\n    Que|\n")
	queue := itemNamed(imports, "Queue")
	if queue == nil || len(queue.AdditionalTextEdits) != 1 {
		t.Fatal(queue)
	}
}
func TestCompletionSurvivesIndependentSyntaxErrors(t *testing.T) {
	items := completeSource(t, "fn answer(input: Int) Int:\n    return inp|\nfn broken(\n")
	if itemNamed(items, "input") == nil {
		t.Fatal(items)
	}
	items = completeSource(t, "import Missing from \"./absent.ms\"\nfn answer(input: Int) Int:\n    return inp|\n")
	if itemNamed(items, "input") == nil {
		t.Fatal(items)
	}
}

func TestCompletionWithMultilineParameters(t *testing.T) {
	for _, source := range []string{
		"fn answer(\n    input: Int,\n) Int:\n    return inp|\nfn broken(\n",
		"import WriteStream from \"@std/io.ms\"\nfn render(\n    arguments: List[String],\n    output: WriteStream\n) Int:\n    let joined = arguments.jo|\n    match output.write(data: \"hello\"):\n",
	} {
		items := completeSource(t, source)
		want := "input"
		if strings.Contains(source, "WriteStream") {
			want = "join"
		}
		if itemNamed(items, want) == nil {
			t.Fatalf("missing %s: %+v", want, items)
		}
	}
}
func TestShadowingCompletionUsesNearestType(t *testing.T) {
	items := completeSource(t, "fn answer(input: Int) Unit:\n    if true:\n        let input = \"text\"\n        inp|\n    return unit\n")
	item := itemNamed(items, "input")
	if item == nil || item.Detail != "String" {
		t.Fatal(item, items)
	}
}

func TestImportedHostAccessorCompletion(t *testing.T) {
	items := completeSource(t, "import stdout from \"@std/io.ms\"\nexport fn main() Int:\n    stdout().wr|\n    return 0\n")
	if itemNamed(items, "write") == nil {
		t.Fatalf("host service result has no write completion: %+v", items)
	}
}
func TestGenericBoundMembers(t *testing.T) {
	items := completeSource(t, "interface Reader:\n    fn read() String\nfn answer[T: Reader](reader: T) String:\n    return reader.|\n")
	if itemNamed(items, "read") == nil {
		t.Fatal(items)
	}
}

func TestUniversalToStringCompletion(t *testing.T) {
	for _, source := range []string{
		"fn text(value: Bool) String:\n    return value.|\n",
		"fn text[T](value: T) String:\n    return value.|\n",
		"interface Named:\n    fn name() String\nfn text(value: Named) String:\n    return value.|\n",
		"type Item:\n    value: Int\nfn text(value: Item) String:\n    return value.|\n",
		"fn text(value: fn() Int) String:\n    return value.|\n",
		"import Queue from \"@std/queues.ms\"\nfn text(value: Queue[Int]) String:\n    return value.|\n",
	} {
		items := completeSource(t, source)
		item := itemNamed(items, "to_string")
		if item == nil || item.Detail != "fn() String" || item.TextEdit.(map[string]any)["newText"] != "to_string()$0" {
			t.Fatalf("missing universal method for %s: %+v", source, items)
		}
	}
}
func BenchmarkMemberCompletion(b *testing.B) {
	source := "fn answer(items: List[String]) Int:\n    return items.\n"
	d := document{"file:///tmp/benchmark-completion.ms", source, 1}
	docs := map[string]document{d.URI: d}
	p := position{1, 17}
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		if _, err := completionAt(d, docs, p, true); err != nil {
			b.Fatal(err)
		}
	}
}
func TestFuzzyMemberCompletion(t *testing.T) {
	items := completeSource(t, "fn size(text: String) Int:\n    return text.bl|\n")
	if itemNamed(items, "byte_length") == nil {
		t.Fatal(items)
	}
}

func TestExpandedStandardMembersAndInterfaceSnippet(t *testing.T) {
	items := completeSource(t, "import HttpClient from \"@std/http.ms\"\nfn work(client: HttpClient) Unit:\n    client.|\n")
	if itemNamed(items, "request_stream") == nil {
		t.Fatal(items)
	}
	items = completeSource(t, "inter|")
	if item := itemNamed(items, "interface"); item == nil || !strings.Contains(item.TextEdit.(map[string]any)["newText"].(string), "fn operation") {
		t.Fatal(items)
	}
}

func TestTimeReceiverCompletion(t *testing.T) {
	for _, test := range []struct {
		typ     string
		methods []string
	}{
		{"Duration", []string{"add", "multiply", "to_nanoseconds", "to_seconds"}},
		{"Instant", []string{"shift", "difference", "compare"}},
		{"Timestamp", []string{"to_string", "unix_seconds", "nanoseconds", "shift", "difference", "compare"}},
	} {
		items := completeSource(t, "import "+test.typ+" from \"@std/time.ms\"\nfn work(value: "+test.typ+") Unit:\n    value.|\n")
		for _, method := range test.methods {
			if itemNamed(items, method) == nil {
				t.Errorf("%s missing %s: %v", test.typ, method, items)
			}
		}
	}
}

func TestGroupedImportCompletion(t *testing.T) {
	for _, source := range []string{"import { ListBuilder, Ma| } from \"@std/collections.ms\"\n", "import {\n    ListBuilder,\n    Ma|,\n} from \"@std/collections.ms\"\n"} {
		items := completeSource(t, source)
		item := itemNamed(items, "MapBuilder")
		if item == nil || item.TextEdit.(map[string]any)["newText"] != "MapBuilder" || len(item.AdditionalTextEdits) != 0 {
			t.Fatal(items)
		}
		for _, name := range []string{"List", "Map", "Set", "ListEntry", "MapEntry", "CollectionError"} {
			if itemNamed(items, name) != nil {
				t.Fatal("offered redundant prelude import", name)
			}
		}
	}
	items := completeSource(t, "import { ListBuilder, | } from \"@std/collections.ms\"\n")
	if itemNamed(items, "ListBuilder") != nil || itemNamed(items, "MapBuilder") == nil {
		t.Fatal(items)
	}
}

func TestCollectionPreludeEditorContracts(t *testing.T) {
	for _, newline := range []string{"\n", "\r\n"} {
		source := strings.ReplaceAll("fn use(values: List[Int], entries: Map[String, Int], unique: Set[Int]) Unit:\n    entries.add(\"a\", 1)\n", "\n", newline)
		d := document{"file:///tmp/collections.ms", source, 1}
		r := analyze(d, map[string]document{d.URI: d})
		if !r.Success() {
			t.Fatal(r.Diagnostics)
		}
		for _, name := range []string{"List", "Map", "Set", "add"} {
			target := navigation(r, d, Position(source, strings.Index(source, name)), "textDocument/definition")
			if target == nil || target.([]any)[0].(map[string]any)["uri"] != "manuscript-stdlib:///collections.ms" {
				t.Fatal(name, target)
			}
		}
	}
	items := completeSource(t, "fn use(entries: Map[String, Int]) Unit:\n    entries.ad|\n")
	item := itemNamed(items, "add")
	if item == nil || !strings.Contains(item.Detail, "String") || !strings.Contains(item.Detail, "Int") || len(item.AdditionalTextEdits) != 0 {
		t.Fatal(item)
	}
	signature := signatureSource(t, "fn use(entries: Map[String, Int]) Unit:\n    entries.add(key: \"a\", value: |\n")
	label := signature["signatures"].([]any)[0].(map[string]any)["label"].(string)
	if label != "entries.add(key: String, value: Int) Map[String, Int]" || signature["activeParameter"] != 1 {
		t.Fatal(signature)
	}
}

func TestStatementKeywordsAreReserved(t *testing.T) {
	reserved := lexer.Keywords()
	for _, word := range statementKeywords {
		if !slices.Contains(reserved, word) {
			t.Errorf("%q is not a reserved word", word)
		}
	}
}

func TestFileFixtureCompletion(t *testing.T) {
	source := `import TestHooks from "@std/testing.ms"
type State:
    count: Int
fn make_fixture() State:
    return State(0)
impl TestHooks for State:
test "one":
    fixture.|
`
	items := completeSource(t, source)
	found := false
	for _, item := range items {
		if item.Label == "count" {
			found = true
		}
	}
	if !found {
		t.Fatalf("fixture field completion missing: %+v", items)
	}
}
