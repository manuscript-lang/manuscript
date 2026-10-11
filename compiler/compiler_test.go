package compiler_test

import (
	"github.com/manuscript-lang/manuscript/compiler"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func fixture(t *testing.T, name string) string {
	t.Helper()
	source, err := os.ReadFile("../tests/e2e/testdata/accept/" + name + ".ms")
	if err != nil {
		t.Fatal(err)
	}
	return string(source)
}
func TestRejectedConformanceVariants(t *testing.T) {
	variants := []struct{ name, fixture, old, replacement, phase string }{
		{"duplicate argument", "cl-01", "deduction: 2,", "amount: 2,", "type"},
		{"missing argument", "cl-01", "deduction: 2,", "", "type"},
		{"unknown argument", "cl-01", "deduction: 2,", "discount: 2,", "type"},
		{"unknown value", "cl-01", "return amount - deduction", "return missing", "resolution"},
		{"mixed numbers", "cl-02", "2 + 3 * 4", "2 + 3.0 * 4.0", "type"},
		{"numeric truthiness", "cl-02", "true or invalid_division", "1 or invalid_division", "type"},
		{"nominal mismatch", "cl-03", "CustomerId(value: \"c1\")", "OrderId(value: \"c1\")", "type"},
		{"missing field", "cl-03", ", name: \"Ada\"", "", "type"},
		{"unknown field", "cl-03", ", name: \"Ada\"", ", active: true, name: \"Ada\"", "type"},
		{"duplicate field", "cl-03", ", name: \"Ada\"", ", name: \"Ada\", name: \"Grace\"", "type"},
		{"unknown pattern field", "cl-03", "name: display_name", "email: display_name", "type"},
		{"duplicate binding", "cl-03", "name: display_name", "name: value", "type"},
		{"list mismatch", "cl-04", "[9, 4]", "[9, 4.0]", "type"},
		{"empty list no context", "cl-04", "let empty: List[Int] = []", "let empty = []", "type"},
		{"static list shape", "cl-04", "let empty: List[Int] = []", "let [only] = [1, 2]", "type"},
		{"function label mismatch", "cl-05", "fn increase(value: Int) -> Int:\n    return value + 1", "fn increase(item: Int) -> Int:\n    return item + 1", "type"},
		{"function argument label", "cl-05", "return transform(value: value)", "return transform(item: value)", "type"},
		{"return incomplete", "cl-06", "    else:\n        panic(message: \"positive value required\")\n", "", "type"},
		{"condition type", "cl-06", "if value > 0:", "if value:", "type"},
		{"return type", "cl-06", "return value", "return true", "type"},
		{"unit return", "cl-06", "    assert value > 0\n", "    return 1\n", "type"},
		{"nonexhaustive", "cl-07", "        Failed(_):\n            return 0\n", "", "type"},
		{"duplicate case", "cl-07", "        Failed(_):", "        Ready(other):", "type"},
		{"payload arity", "cl-07", "Ready(value):", "Ready(value, extra):", "type"},
		{"case argument name", "cl-07", "Outcome.Ready(value: 8)", "Outcome.Ready(amount: 8)", "type"},
		{"unreachable wildcard", "cl-07", "            return 0\n", "            return 0\n        _:\n            return 0\n", "type"},
		{"noniterable", "cl-08", "for value in values:", "for value in 3:", "type"},
		{"immutable iteration", "cl-08", "total = total + value", "value = 4", "type"},
		{"break outside loop", "cl-08", "    assert selected_sum(values: []) == 0", "    break", "type"},
		{"generic arity", "cl-09", "Box[Int](value: 6)", "Box[Int, String](value: 6)", "type"},
		{"generic field", "cl-09", "Box[Int](value: 6)", "Box[String](value: 6)", "type"},
		{"explicit specialization mismatch", "cl-09", "unwrap[Int](box: box)", "unwrap[String](box: box)", "type"},
		{"conflicting inference", "cl-09", "same(left: 6, right: 6)", "same(left: 6, right: 6.0)", "type"},
		{"missing equal bound", "cl-09", "Shareable & Equal", "Shareable", "type"},
		{"unknown type parameter", "cl-09", "    value: T", "    value: U", "resolution"},
		{"result context inference forbidden", "cl-09-2", "absent[Int]()", "absent()", "type"},
		{"implicit contract conversion", "cl-10", "operation: same_view", "operation: offset", "type"},
		{"missing implementation", "cl-10", "impl Increment for Offset:\n    fn apply(value: Int) -> Int:\n        return value + self.delta\n", "", "type"},
		{"implementation labels", "cl-10", "fn apply(value: Int) -> Int:\n        return value + self.delta", "fn apply(item: Int) -> Int:\n        return item + self.delta", "type"},
		{"contract no receiver", "cl-10", "Increment(value: offset)", "Increment()", "type"},
		{"implementation generic signature", "cl-10a", "impl[T] ReadValue[T] for Box[T]:", "impl[T] ReadValue[Int] for Box[T]:", "type"},
		{"implementation missing bound", "cl-10a", "impl[T: Equal]", "impl[T]", "type"},
		{"implementation unavailable", "cl-10a", "fn compare[T: Equal]", "fn compare[T]", "resolution"},
		{"unused impl variable", "cl-10a", "impl[T]", "impl[T, U]", "type"},
		{"blanket implementation", "cl-10a", "ReadValue[T] for Box[T]", "ReadValue[T] for T", "type"},
		{"shared view missing proof", "cl-10b", "fn shared_view[T: ReadValue[Int] & Shareable]", "fn shared_view[T: ReadValue[Int]]", "type"},
		{"plain view cannot recover proof", "cl-10b", "value: shared)", "value: plain)", "type"},
		{"function field not shareable", "cl-10b", "ReadValue[Int](value: callback)", "(ReadValue[Int] & Shareable)(value: callback)", "type"},
		{"plain contract list", "cl-10b", "List[ReadValue[Int] & Shareable]", "List[ReadValue[Int]]", "type"},
		{"shared field exact", "cl-10b", "SharedReader(reader: identity)", "SharedReader(reader: plain)", "type"},
		{"unguarded recursion", "cl-11", "children: List[Tree[T]]", "children: Tree[T]", "type"},
		{"expanding recursion", "cl-11", "children: List[Tree[T]]", "children: List[Tree[List[T]]]", "type"},
		{"map key binding type", "cl-12", "let label: String = key", "let label: Int = key", "type"},
		{"float set element", "cl-12", "Set[Int]", "Set[Float]", "type"},
		{"collection map key", "cl-12", "Map[String, Int]", "Map[Set[Int], Int]", "type"},
		{"unit exactness", "cl-13", "let no_value: Unit = unit", "let no_value: Unit = 0", "type"},
		{"int positive range", "cl-13", "let no_value: Unit = unit", "let too_large = 9223372036854775808", "type"},
		{"float literal range", "cl-13", "let no_value: Unit = unit", "let too_large = 1e400", "type"},
		{"result error invariant", "cl-14", "fn doubled(value: Int) -> Result[Int, Problem]", "fn doubled(value: Int) -> Result[Int, OtherProblem]", "type"},
		{"result payload", "cl-14", "ok(value: value)", "ok(value: true)", "type"},
		{"try nonresult", "cl-14", "try checked(value: value)", "try value", "type"},
		{"try no backward context", "cl-14", "let accepted = try checked(value: value)", "let accepted: Int = try ok(value: 3)", "type"},
		{"record equality eligibility", "cl-15", "let callback = Callback(handler: increment)", "let callback = Callback(handler: increment)\n    assert callback == callback", "type"},
		{"float hashing", "cl-15", "preserve_key(value: \"key\") == \"key\"", "preserve_key(value: 1.0) == 1.0", "type"},
		{"list hashing", "cl-15", "preserve_key(value: \"key\") == \"key\"", "preserve_key(value: [1, 2]) == [1, 2]", "type"},
		{"optional invariance", "cl-15", "let missing: Optional[Int] = none", "let wrong: Optional[Float] = present", "type"},
		{"result insufficient context", "cl-16", "let success: Result[Int, String]", "let success", "type"},
		{"none insufficient context", "cl-16", "let absent: Optional[Int]", "let absent", "type"},
		{"optional payload context", "cl-16", "some(value: \"Ada\")", "some(value: 3)", "type"},
		{"no result wrapping", "cl-16", "ok(value: 3)", "3", "type"},
		{"never fallthrough", "cl-17", "let impossible: Int = panic(message: \"initializer cannot return\")", "let impossible: Int = 0", "type"},
		{"two never operands", "cl-17", "let impossible: Int = panic(message: \"initializer cannot return\")", "let impossible: Int = panic(message: \"left\") + panic(message: \"right\")", "type"},
		{"unary never no evidence", "cl-17", "let impossible: Int = panic(message: \"initializer cannot return\")", "let impossible: Int = -panic(message: \"stop\")", "type"},
		{"never short circuit fallthrough", "cl-17", "let impossible: Int = panic(message: \"initializer cannot return\")", "let possible: Bool = false and panic(message: \"skipped\")", "type"},
		{"conservative loop exit", "cl-17", "while true:", "while not false:", "type"},
	}
	for _, v := range variants {
		t.Run(v.name, func(t *testing.T) {
			source := fixture(t, v.fixture)
			if !strings.Contains(source, v.old) {
				t.Fatalf("mutation is stale: %q", v.old)
			}
			source = strings.Replace(source, v.old, v.replacement, 1)
			result := compiler.CompileSource(v.name+".ms", source, compiler.Options{})
			if result.Success() {
				t.Fatal("accepted rejected variant")
			}
			found := false
			for _, d := range result.Diagnostics {
				if d.Phase == v.phase {
					found = true
					if d.Position.Line < 1 || d.Position.Column < 1 {
						t.Error("missing diagnostic position")
					}
				}
			}
			if !found {
				t.Fatalf("expected %s diagnostic, got %v", v.phase, result.Diagnostics)
			}
		})
	}
}
func TestCompilerPublicAPIs(t *testing.T) {
	result := compiler.CompileSource("file.ms", "fn value() -> Int:\n    return 3\n", compiler.Options{})
	if !result.Success() || !strings.Contains(result.Source, "package main") {
		t.Fatal(result.Diagnostics)
	}
	result = compiler.CompileSource("file.ms", "fn value() -> Int:\n    return missing\n", compiler.Options{})
	if result.Success() || result.Source != "" {
		t.Fatal("emitted unchecked source")
	}
}
func write(t *testing.T, root, path, text string) {
	t.Helper()
	target := filepath.Join(root, path)
	if err := os.MkdirAll(filepath.Dir(target), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(target, []byte(text), 0600); err != nil {
		t.Fatal(err)
	}
}
func TestModulesAndProjectPaths(t *testing.T) {
	root := t.TempDir()
	write(t, root, "ms.toml", "[project]\nname = \"example\"\nsource = \"./src\"\nentry = \"./src/main.ms\"\n[aliases]\n\"@domain\" = \"./src/domain\"\n\"@value\" = \"./src/domain/value.ms\"\n")
	write(t, root, "src/domain/value.ms", "export type Identity:\n    value: Int\n\nexport fn read(value: Identity) -> Int:\n    return value.value\n")
	write(t, root, "src/main.ms", "import Identity from \"@value\"\nimport read from \"@domain/value.ms\"\nimport Process from \"@std/cli.ms\"\n\nexport fn main(process: Process) -> Int:\n    return read(value: Identity(value: 0))\n")
	result := compiler.CompileFile(filepath.Join(root, "ms.toml"), compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	if len(result.Program.Modules) != 2 {
		t.Fatal("aliases created duplicate modules")
	}
	write(t, root, "src/domain/value.ms", "type Identity:\n    value: Int\n")
	result = compiler.CompileFile(filepath.Join(root, "ms.toml"), compiler.Options{})
	if result.Success() {
		t.Fatal("imported private declarations")
	}
}

func TestGenericRecursionAndNamespaceRules(t *testing.T) {
	for name, source := range map[string]string{
		"expanding calls":               "import List from \"@std/collections.ms\"\nfn recurse[T: Shareable](value: T) -> Unit:\n    recurse(value: [value])\n",
		"expanding stored function":     "import List from \"@std/collections.ms\"\nfn recurse[T: Shareable](value: T) -> Unit:\n    let next = recurse[List[T]]\n",
		"intrinsic parameter":           "type Box[Int]:\n    value: Int\n",
		"intrinsic declaration":         "type Int:\n    value: String\n",
		"intrinsic bound target":        "type Data:\n    value: Int\nimpl Equal for Data:\n    fn compare() -> Unit:\n        return\n",
		"case ambiguity":                "type First:\n    case Ready(value: Int)\ntype Second:\n    case Ready(value: Int)\nfn wrong() -> First:\n    return Ready(value: 1)\n",
		"generic overlap":               "type Read[T]:\n    fn get() -> T\ntype Box[T]:\n    value: T\nimpl[T] Read[T] for Box[T]:\n    fn get() -> T:\n        return self.value\nimpl Read[Int] for Box[Int]:\n    fn get() -> Int:\n        return self.value\n",
		"nested function field sharing": "type Box[T]:\n    value: T\ntype Read:\n    fn get() -> Int\nimpl[T] Read for Box[T]:\n    fn get() -> Int:\n        return 1\nfn one() -> Int:\n    return 1\ntest \"invalid sharing\":\n    let value = Box(value: Box(value: one))\n    let shared = (Read & Shareable)(value: value)\n",
	} {
		t.Run(name, func(t *testing.T) {
			result := compiler.CompileSource(name+".ms", source, compiler.Options{})
			if result.Success() {
				t.Fatal("accepted invalid module")
			}
		})
	}
	valid := "fn recurse[T](value: T, count: Int) -> T:\n    if count == 0:\n        return value\n    return recurse(value: value, count: count - 1)\n"
	if result := compiler.CompileSource("regular.ms", valid, compiler.Options{}); !result.Success() {
		t.Fatal(result.Diagnostics)
	}
}
func FuzzCompile(f *testing.F) {
	for _, s := range []string{"fn f() -> Int:\n    return 1\n", "type Box[T]:\n    value: T\nfn f() -> Box[Int]:\n    return Box(value: 1)\n", "import List from \"@std/collections.ms\"\ntest \"list\":\n    let values = [1, 2]\n    assert values.length() == 2\n"} {
		f.Add(s)
	}
	f.Fuzz(func(t *testing.T, source string) {
		if len(source) > 16000 {
			t.Skip()
		}
		_ = compiler.CompileSource("fuzz.ms", source, compiler.Options{})
	})
}

func TestDisjointImplementations(t *testing.T) {
	for name, source := range map[string]string{
		"finite types": `import List from "@std/collections.ms"
type Read[T]:
    fn get() -> Int
type Pair[A, B]:
    left: A
    right: B
impl[T] Read[T] for Pair[T, T]:
    fn get() -> Int:
        return 1
impl[U: Shareable] Read[U] for Pair[U, List[U]]:
    fn get() -> Int:
        return 2
`,
		"function labels": `type Read:
    fn get() -> Int
type Box[T]:
    value: T
impl Read for Box[fn(left: Int) -> Int]:
    fn get() -> Int:
        return 1
impl Read for Box[fn(right: Int) -> Int]:
    fn get() -> Int:
        return 2
`,
	} {
		t.Run(name, func(t *testing.T) {
			result := compiler.CompileSource(name+".ms", source, compiler.Options{})
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
		})
	}
}

func TestReproducibleOutput(t *testing.T) {
	source := fixture(t, "closures")
	first := compiler.CompileSource("closures.ms", source, compiler.Options{Tests: true})
	if !first.Success() {
		t.Fatal(first.Diagnostics)
	}
	for i := 0; i < 20; i++ {
		result := compiler.CompileSource("closures.ms", source, compiler.Options{Tests: true})
		if result.Source != first.Source {
			t.Fatal("compilation depends on map iteration order")
		}
	}
	var output string
	for i := 0; i < 2; i++ {
		root := t.TempDir()
		write(t, root, "ms.toml", "[project]\nname = \"example\" # comment\nsource = \"./src\"\nentry = \"./src/main.ms\"\n")
		write(t, root, "src/main.ms", source)
		result := compiler.CompileFile(filepath.Join(root, "ms.toml"), compiler.Options{Tests: true})
		if !result.Success() {
			t.Fatal(result.Diagnostics)
		}
		if i == 0 {
			output = result.Source
		} else if output != result.Source {
			t.Fatal("compilation depends on absolute checkout path")
		}
	}
}

func TestRejectedModuleBoundaries(t *testing.T) {
	for _, name := range []string{"escape", "symlink", "cycle", "missing extension", "reserved alias", "duplicate table", "orphan"} {
		t.Run(name, func(t *testing.T) {
			root := t.TempDir()
			manifest := "[project]\nname = \"example\"\nsource = \"./src\"\nentry = \"./src/main.ms\"\n"
			main := "import value from \"./other.ms\"\nfn read() -> Int:\n    return value()\n"
			other := "export fn value() -> Int:\n    return 1\n"
			switch name {
			case "escape", "symlink":
				outside := t.TempDir()
				write(t, outside, "other.ms", other)
				if name == "escape" {
					relative, err := filepath.Rel(filepath.Join(root, "src"), filepath.Join(outside, "other.ms"))
					if err != nil {
						t.Fatal(err)
					}
					main = strings.ReplaceAll(main, "./other.ms", filepath.ToSlash(relative))
				} else {
					write(t, root, "src/main.ms", main)
					if err := os.Symlink(filepath.Join(outside, "other.ms"), filepath.Join(root, "src/other.ms")); err != nil {
						t.Fatal(err)
					}
				}
			case "cycle":
				other = "import read from \"./main.ms\"\n" + other
			case "missing extension":
				main = strings.ReplaceAll(main, "./other.ms", "./other")
			case "reserved alias":
				manifest += "[aliases]\n\"@std\" = \"./src\"\n"
			case "duplicate table":
				manifest += "[project]\n"
			case "orphan":
				other = "export type Read:\n    fn get() -> Int\nexport type Box:\n    value: Int\n"
				main = "import Read from \"./other.ms\"\nimport Box from \"./other.ms\"\nimpl Read for Box:\n    fn get() -> Int:\n        return 1\n"
			}
			write(t, root, "ms.toml", manifest)
			write(t, root, "src/main.ms", main)
			if name != "symlink" {
				write(t, root, "src/other.ms", other)
			}
			result := compiler.CompileFile(filepath.Join(root, "ms.toml"), compiler.Options{Tests: true})
			if result.Success() {
				t.Fatal("accepted invalid module boundary")
			}
		})
	}
}

func TestServiceBoundaries(t *testing.T) {
	for name, source := range map[string]string{
		"opaque constructor fields": "import Queue from \"@std/queues.ms\"\ntest \"opaque\":\n    let queue = Queue[Int](capacity: 1)\n    let capacity = queue.capacity\n",
		"pool record forbidden":     "import Pool from \"@std/pools.ms\"\ntest \"pool\":\n    let pool = Pool(resources: [1])\n",
		"pool generic representation": `import File from "@std/io.ms"
import List from "@std/collections.ms"
import Pool from "@std/pools.ms"
fn make[T: File & Shareable](resources: List[T]) -> Unit:
    with pool = Pool(resources: resources):
        return
`,

		"builder not shareable":  "import ListBuilder from \"@std/builders.ms\"\nimport parallel from \"@std/tasks.ms\"\ntest \"builder\":\n    let builder = ListBuilder[Int]()\n    let operation = fn() -> Int:\n        return builder.freeze().length()\n    let result = parallel(tasks: [operation])\n",
		"stored HTTP admission":  "import Network from \"@std/http.ms\"\nfn invalid(network: Network & Shareable) -> Unit:\n    let serve = network.serve\n",
		"unproved HTTP callback": "import Network from \"@std/http.ms\"\nimport HttpRequest from \"@std/http.ms\"\nimport HttpResponse from \"@std/http.ms\"\nfn invalid(network: Network & Shareable, handler: fn(request: HttpRequest) -> HttpResponse) -> Unit:\n    network.serve(address: \"127.0.0.1:0\", handler: handler, limit: 1, max_body_bytes: 10, max_response_bytes: 10, timeout: 1.seconds, grace: 0.seconds)\n",
	} {
		t.Run(name, func(t *testing.T) {
			result := compiler.CompileSource(name+".ms", source, compiler.Options{})
			if result.Success() {
				t.Fatal("accepted an invalid service boundary")
			}
		})
	}
}
func TestPinsNativeCacheAndBuildMetadata(t *testing.T) {
	root := t.TempDir()
	write(t, root, "ms.toml", "[project]\nname = \"cache\"\nsource = \"./src\"\nentry = \"./src/main.ms\"\n")
	source := "import Process from \"@std/cli.ms\"\nexport fn main(process: Process) -> Int:\n    return 0\n"
	write(t, root, "src/main.ms", source)
	result := compiler.CompileFile(filepath.Join(root, "ms.toml"), compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	binary := filepath.Join(root, "program")
	cache := filepath.Join(root, "cache")
	if _, err := compiler.BuildChecked(result, binary, cache, false); err == nil {
		t.Fatal("project built without explicit pins")
	}
	if err := compiler.WritePin(root); err != nil {
		t.Fatal(err)
	}
	if err := compiler.CheckPin(root); err != nil {
		t.Fatal(err)
	}
	first, err := compiler.BuildChecked(result, binary, cache, false)
	if err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(binary)
	if err != nil {
		t.Fatal(err)
	}
	second, err := compiler.BuildChecked(result, binary, cache, false)
	if err != nil || first.BuildID != second.BuildID {
		t.Fatal("cache miss or identity changed", err)
	}
	after, _ := os.Stat(binary)
	if after.ModTime() != info.ModTime() {
		t.Fatal("unchanged binary was rewritten")
	}
	if err := compiler.VerifyBuild(binary, map[string]string{"src/main.ms": source, "ms.toml": result.Configuration}); err != nil {
		t.Fatal(err)
	}
	if err := compiler.VerifyBuild(binary, map[string]string{"src/main.ms": source + "# edited\n", "ms.toml": result.Configuration}); err == nil {
		t.Fatal("stale source accepted")
	}
	write(t, root, "cache/"+first.BuildID+".bin", "corrupt")
	if _, err := compiler.BuildChecked(result, binary, cache, false); err != nil {
		t.Fatal("corrupt cache was not rebuilt", err)
	}
	write(t, root, "program", "corrupt")
	if err := compiler.VerifyBuild(binary, map[string]string{"src/main.ms": source, "ms.toml": result.Configuration}); err == nil {
		t.Fatal("wrong executable accepted")
	}
	write(t, root, "ms.lock", "{}\n")
	if err := compiler.CheckPin(root); err == nil {
		t.Fatal("mismatched pins accepted")
	}
}
