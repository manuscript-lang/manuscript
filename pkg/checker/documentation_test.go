package checker

import (
	"encoding/json"
	"slices"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestStandardLibrarySnapshot(t *testing.T) {
	modules := StandardLibrary()
	exports := map[string]APIDeclaration{}
	count := 0
	for _, module := range modules {
		for _, d := range module.Declarations {
			exports[module.Path+"#"+d.Name] = d
			if module.Path != "prelude" {
				count++
			}
		}
	}
	expected := 0
	for _, symbols := range standardModules {
		for _, symbol := range symbols {
			if symbol.Export {
				expected++
			}
		}
	}
	if count != expected {
		t.Fatalf("captured %d exports, want %d", count, expected)
	}
	for _, key := range []string{"@std/collections.ms#List", "@std/tasks.ms#Scheduler", "@std/cli.ms#arguments", "prelude#String", "prelude#Optional", "prelude#Result", "prelude#Error"} {
		d, ok := exports[key]
		if !ok {
			t.Fatalf("missing %s", key)
		}
		if key == "prelude#String" && (!slices.Contains(d.Operations, "trim: fn()->String") || !slices.Contains(d.Operations, "byte_length: fn()->Int")) {
			t.Fatalf("missing intrinsic operation: %+v", d)
		}
		if key == "@std/collections.ms#List" && (len(d.Parameters) != 1 || d.Parameters[0] != "T" || !slices.Contains(d.Operations, "map[U]: fn(transform: fn(value: T)->U)->List[U]") || !slices.Contains(d.Operations, "at: fn(index: Int)->Optional[T]")) {
			t.Fatalf("lost bounds or native methods: %+v", d)
		}
	}
	for _, pair := range [][2]string{{"Optional", "optional"}, {"Result", "result"}, {"Error", "errors"}, {"List", "collections"}, {"Map", "collections"}} {
		if exports["prelude#"+pair[0]].Declaration != exports["@std/"+pair[1]+".ms#"+pair[0]].Declaration {
			t.Fatalf("prelude %s lost its source declaration", pair[0])
		}
	}
	// Editing a snapshot must never change checker contracts.
	modules[0].Declarations[0].Name = "changed"
	again := StandardLibrary()
	if again[0].Declarations[0].Name == "changed" {
		t.Fatal("snapshot aliases registry")
	}
	a, _ := json.Marshal(again)
	b, _ := json.Marshal(StandardLibrary())
	if string(a) != string(b) {
		t.Fatal("output depends on map or candidate order")
	}
}

func TestDocumentationUsesManuscriptDeclarations(t *testing.T) {
	exports := map[string]APIDeclaration{}
	for _, module := range StandardLibrary() {
		for _, d := range module.Declarations {
			exports[module.Path+"#"+d.Name] = d
			if d.Declaration == "" {
				t.Errorf("missing declaration for %s#%s", module.Path, d.Name)
				continue
			}
			parsed, err := parser.Parse(module.Path, d.Declaration)
			if err != nil {
				t.Fatalf("%s#%s is not Manuscript syntax: %v\n%s", module.Path, d.Name, err, d.Declaration)
			}
			if len(parsed.Declarations) != 1 || parsed.Declarations[0].Name != d.Name {
				t.Fatalf("declaration identity changed for %s#%s: %s", module.Path, d.Name, d.Declaration)
			}
		}
	}
	for key, want := range map[string]string{
		"@std/net.ms#DatagramSocket": "interface DatagramSocket:\n    fn address() -> String\n    fn close() -> Unit\n    fn receive(max_bytes: Optional[Int64] = none, timeout: Optional[Duration] = none) -> Result[Datagram, NetworkError]\n    fn send(data: Bytes, address: String, timeout: Optional[Duration] = none) -> Result[Unit, NetworkError]\n",
		"@std/net.ms#DnsRecord":      "type DnsRecord:\n    kind: String\n    value: String\n    priority: Int\n    weight: Int\n    port: Int\n",
		"@std/optional.ms#Optional":  "type Optional[T]:\n    case some(value: T)\n    case none\n    fn is_some() -> Bool:\n    fn is_none() -> Bool:\n    fn unwrap() -> T:\n    fn unwrap_or(fallback: T) -> T:\n    fn unwrap_or_else(create: fn() -> T) -> T:\n    fn map[U](transform: fn(value: T) -> U) -> Optional[U]:\n    fn and_then[U](transform: fn(value: T) -> Optional[U]) -> Optional[U]:\n    fn or_else(create: fn() -> Optional[T]) -> Optional[T]:\n    fn ok_or[E](cause: E) -> Result[T, E]:\n    fn ok_or_else[E](create: fn() -> E) -> Result[T, E]:\n",
	} {
		if got := exports[key].Declaration; got != want {
			t.Errorf("%s declaration:\ngot %s\nwant %s", key, got, want)
		}
	}
	for key, want := range map[string]string{
		"@std/time.ms#Duration":    "    fn to_nanoseconds() -> Int",
		"@std/time.ms#Instant":     "    fn difference(right: Instant) -> Duration",
		"@std/time.ms#Timestamp":   "    fn shift(duration: Duration) -> Result[Timestamp, TimeError]",
		"@std/collections.ms#Map":  "type Map[T: Hashable, U]:",
		"@std/collections.ms#List": "    fn group_by[K: Hashable](key: fn(value: T) -> K) -> Map[K, List[T]]",
		"@std/bytes.ms#Bytes":      "    fn values() -> List[Int]",
		"prelude#String":           "    fn to_bytes() -> Bytes",
	} {
		if !strings.Contains(exports[key].Declaration, want) {
			t.Errorf("%s lost source syntax %q: %s", key, want, exports[key].Declaration)
		}
	}
}

func TestBytesValuesDocumentationIsAnOperation(t *testing.T) {
	for _, module := range StandardLibrary() {
		if module.Path != "@std/bytes.ms" {
			continue
		}
		for _, d := range module.Declarations {
			if d.Name == "Bytes" {
				if len(d.Fields) != 0 || !slices.Contains(d.Operations, "values: fn()->List[Int]") {
					t.Fatalf("Bytes values must be callable, not a data field: %+v", d)
				}
				return
			}
		}
	}
	t.Fatal("missing Bytes documentation")
}

func TestModuleDocumentationRetainsDefaults(t *testing.T) {
	source := `fn helper(left: Int, right: Int) -> Int:
    return left + right
export fn defaults(first: Int = -3, second: Int = helper(left: first, right: 2), text: String = "literal, )", callback: fn(value: Int) -> Int = (fn(value: Int) -> Int:
    return value + 1
)) -> Int:
    return callback(second)
`
	module, err := parser.Parse("defaults.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	program := Check([]*syntax.Module{module}, nil)
	if len(program.Diagnostics) != 0 {
		t.Fatal(program.Diagnostics)
	}
	documentation := ModuleDocumentation(program)
	if len(documentation) != 1 || len(documentation[0].Declarations) != 1 {
		t.Fatal(documentation)
	}
	declaration := documentation[0].Declarations[0].Declaration
	for _, want := range []string{"first: Int = -3", "second: Int = helper(left: first, right: 2)", `text: String = "literal, )"`, "callback: fn(value: Int) -> Int = (fn(value: Int) -> Int:\n    return value + 1\n)"} {
		if !strings.Contains(declaration, want) {
			t.Errorf("default missing %q: %s", want, declaration)
		}
	}
	if strings.Contains(declaration, "return callback") {
		t.Fatal("included function body", declaration)
	}
}

func TestRecordDefaultDocumentation(t *testing.T) {
	source := `export type Options:
    count: Int = 3
    total: Int = count + 1
    label: String = "literal, )"
`
	module, err := parser.Parse("fields.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	program := Check([]*syntax.Module{module}, nil)
	if len(program.Diagnostics) != 0 {
		t.Fatal(program.Diagnostics)
	}
	docs := ModuleDocumentation(program)
	if len(docs) != 1 || len(docs[0].Declarations) != 1 || docs[0].Declarations[0].Declaration != strings.TrimPrefix(source, "export ") {
		t.Fatal("field default spelling changed", docs)
	}
}

func TestModuleDocumentationCapturesLeadingComments(t *testing.T) {
	source := `# Adds two numbers.
# Never rounds.
export fn add(a: Int, b: Int) -> Int:
    return a + b

# Detached by a blank line.

export fn sub(a: Int, b: Int) -> Int:
    return a - b

# Not a doc comment: private declaration.
fn helper() -> Int:
    return 1

export fn bare() -> Int:
    return 0
`
	module, err := parser.Parse("docs.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	program := Check([]*syntax.Module{module}, nil)
	if len(program.Diagnostics) != 0 {
		t.Fatal(program.Diagnostics)
	}
	docs := map[string]string{}
	for _, d := range ModuleDocumentation(program)[0].Declarations {
		docs[d.Name] = d.Doc
	}
	if docs["add"] != "Adds two numbers.\nNever rounds." {
		t.Errorf("add doc = %q", docs["add"])
	}
	if docs["sub"] != "" || docs["bare"] != "" {
		t.Errorf("detached or absent comments leaked: %q %q", docs["sub"], docs["bare"])
	}
}
