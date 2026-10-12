package checker

import (
	"encoding/json"
	"slices"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/parser"
	"github.com/manuscript-lang/manuscript/syntax"
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
	for _, key := range []string{"@std/collections.ms#List", "@std/tasks.ms#Background", "@std/cli.ms#Process", "prelude#String"} {
		d, ok := exports[key]
		if !ok {
			t.Fatalf("missing %s", key)
		}
		if key == "prelude#String" && (!slices.Contains(d.Operations, "trim: fn()->String") || !slices.Contains(d.Operations, "byte_length: fn()->Int")) {
			t.Fatalf("missing intrinsic operation: %+v", d)
		}
		if key == "@std/collections.ms#List" && (len(d.Parameters) != 1 || d.Parameters[0] != "T" || !slices.Contains(d.Operations, "map[U]: fn(transform: fn(value: T)->U)->List[U]") || !slices.Contains(d.Operations, "get: fn(index: Int)->Optional[T]")) {
			t.Fatalf("lost bounds or native methods: %+v", d)
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
				if module.Path != "@std/tasks.ms" || d.Name != "parallel" {
					t.Errorf("missing declaration for %s#%s", module.Path, d.Name)
				}
				continue
			}
			parsed, err := parser.ParseLibrary(module.Path, d.Declaration)
			if err != nil {
				t.Fatalf("%s#%s is not Manuscript syntax: %v\n%s", module.Path, d.Name, err, d.Declaration)
			}
			if len(parsed.Declarations) != 1 || parsed.Declarations[0].Name != d.Name {
				t.Fatalf("declaration identity changed for %s#%s: %s", module.Path, d.Name, d.Declaration)
			}
		}
	}
	for key, want := range map[string]string{
		"@std/net.ms#DatagramSocket": "interface DatagramSocket:\n    fn address() -> String\n    fn close() -> Unit\n    fn receive(max_bytes: Int) -> Result[Datagram, NetworkError]\n    fn receive_timeout(max_bytes: Int, timeout: Duration) -> Result[Datagram, NetworkError]\n    fn send(data: Bytes, address: String) -> Result[Unit, NetworkError]\n    fn send_timeout(data: Bytes, address: String, timeout: Duration) -> Result[Unit, NetworkError]\n",
		"@std/net.ms#DnsRecord":      "type DnsRecord:\n    kind: String\n    value: String\n    priority: Int\n    weight: Int\n    port: Int\n",
		"@std/optional.ms#Optional":  "type Optional[T]:\n    case some(value: T)\n    case none\n",
		"@std/time.ms#Duration":      "type Duration\n",
		"@std/collections.ms#fold":   "fn fold[T, A](values: List[T], initial: A, step: fn(accumulator: A, value: T) -> A) -> A\n",
	} {
		if got := exports[key].Declaration; got != want {
			t.Errorf("%s declaration:\ngot %s\nwant %s", key, got, want)
		}
	}
	for key, want := range map[string]string{
		"@std/collections.ms#Map":  "type Map[T: Hashable, U]:",
		"@std/collections.ms#List": "    fn group_by[K: Hashable](key: fn(value: T) -> K) -> Map[K, List[T]]",
		"@std/bytes.ms#Bytes":      "    values: List[Int]",
		"prelude#String":           "    fn to_bytes() -> Bytes",
	} {
		if !strings.Contains(exports[key].Declaration, want) {
			t.Errorf("%s lost source syntax %q: %s", key, want, exports[key].Declaration)
		}
	}
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
