package compiler

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPreludeRetainsCaseInferenceAndLookupRules(t *testing.T) {
	for name, source := range map[string]string{
		"none needs payload type":                "fn f() -> Unit:\n    let missing = none\n",
		"ok needs error type":                    "fn f() -> Unit:\n    let result = ok(value: 1)\n",
		"error needs success type":               "fn f() -> Unit:\n    let result = error(cause: \"failed\")\n",
		"ordinary errors need an implementation": "fn f() -> Error:\n    return \"failed\"\n",
		"cases remain ambiguous":                 "type Other:\n    case some(value: Int)\nfn f() -> Optional[Int]:\n    return some(value: 1)\n",
	} {
		t.Run(name, func(t *testing.T) {
			result := CompileSource("prelude.ms", source, Options{AnalyzeOnly: true})
			if result.Success() {
				t.Fatal("accepted invalid prelude use")
			}
			if name == "cases remain ambiguous" && !strings.Contains(result.Diagnostics[0].Message, "ambiguous alternative case") {
				t.Fatal(result.Diagnostics)
			}
		})
	}
}

func TestCollectionPreludeAndShadowing(t *testing.T) {
	for name, source := range map[string]string{
		"unimported literals and annotations": `fn use() -> Int:
    let nested: List[List[Int]] = [[], [1]]
    let empty: Map[String, Int] = {}
    return Map[String, Int]().add("a", nested[1].unwrap()[0].unwrap()).get("a").unwrap()
`,
		"unimported set annotations and methods": `type Selection:
    values: Set[Int]
fn keep[T: Hashable](values: Set[T], value: T) -> Set[T]: values.add(value)
fn use() -> Set[Int]:
    let values: Set[Int] = Set[Int]()
    let nested: List[Set[Int]] = [values]
    return keep(nested[0].unwrap(), 1)
`,
		"contextual set construction": `fn use() -> Set[Int]:
    let values: Set[Int] = Set()
    return values.add(1)
`,
		"local set retains its own bounds": `type Set[T]:
    value: T
fn use() -> Set[List[Int]]: Set([1])
`,
		"ordinary types": `type List[T]:
    value: T
type Map[K, V]:
    key: K
    value: V
type Set[T]:
    value: T
fn use() -> Int: List(3).value + Map("a", 4).value + Set(5).value
`,
		"function names": `fn List(value: Int) -> Int: value
fn Map(value: Int) -> Int: value
fn Set(value: Int) -> Int: value
fn use() -> Int: List(3) + Map(4) + Set(5)
`,
		"local callable bindings": `fn f() -> Int:
    let List = fn(value: Int) -> Int: value
    let Map = fn(value: Int) -> Int: value
    let Set = fn(value: Int) -> Int: value
    let items = [1]
    let entries = {1: 2}
    return List(3) + Map(4) + Set(5) + items.length + entries.length
`,
		"type parameters": `fn identity[List, Map, Set](left: List, right: Map, other: Set) -> Set: other
`,
	} {
		t.Run(name, func(t *testing.T) {
			r := CompileSource("prelude.ms", source, Options{})
			if !r.Success() {
				t.Fatal(r.Diagnostics)
			}
		})
	}
	for name, source := range map[string]string{
		"list type shadows literal":    "type List[T]:\n    value: T\nfn f() -> Unit:\n    let xs = [1]\n",
		"map type shadows literal":     "type Map[K, V]:\n    value: V\nfn f() -> Unit:\n    let xs = {1: 2}\n",
		"wrong value":                  "fn f(m: Map[String, Int]) -> Unit:\n    m.add(\"a\", true)\n",
		"unhashable key":               "fn f(m: Map[List[Int], Int]) -> Unit:\n    return\n",
		"local map has no native add":  "type Map[K,V]:\n    value: V\nfn f(m: Map[String,Int]) -> Unit:\n    m.add(\"a\", 1)\n",
		"missing value":                "fn f(m: Map[Int,Int]) -> Unit:\n    m.add(1)\n",
		"duplicate imports":            "import List from \"@std/collections.ms\"\nimport List from \"@std/collections.ms\"\n",
		"import declaration collision": "import Map from \"@std/collections.ms\"\ntype Map[K,V]:\n    value: V\n",
		"wrong set element":            "fn f(values: Set[Int]) -> Unit:\n    values.add(true)\n",
		"unhashable set element":       "fn f(values: Set[List[Int]]) -> Unit:\n    return\n",
		"local set has no native add":  "type Set[T]:\n    value: T\nfn f(values: Set[Int]) -> Unit:\n    values.add(1)\n",
		"set needs element type":       "fn f() -> Unit:\n    let values = Set()\n",
		"duplicate set imports":        "import Set from \"@std/collections.ms\"\nimport Set from \"@std/collections.ms\"\n",
		"set import collision":         "import Set from \"@std/collections.ms\"\ntype Set[T]:\n    value: T\n",
	} {
		t.Run(name, func(t *testing.T) {
			r := CompileSource("prelude.ms", source, Options{AnalyzeOnly: true})
			if r.Success() {
				t.Fatal("accepted invalid source")
			}
			if strings.Contains(name, "duplicate") || strings.Contains(name, "collision") {
				found := false
				for _, diagnostic := range r.Diagnostics {
					if strings.Contains(diagnostic.Message, "duplicate or intrinsic name") {
						found = true
					}
				}
				if !found {
					t.Fatal("import policy hid the ordinary collision", r.Diagnostics)
				}
			}
			if strings.Contains(name, "shadows literal") && (len(r.Diagnostics) != 1 || !strings.Contains(r.Diagnostics[0].Message, "rename the shadowing")) {
				t.Fatal(r.Diagnostics)
			}
		})
	}
}

func TestMapAddDirectAndReorderedLowering(t *testing.T) {
	r := CompileSource("add.ms", `fn use(m: Map[String, Int]) -> Unit:
    m.add("a", 1)
    m.add(key: "b", value: 2)
    m.add(value: 3, key: "c")
    let add = m.add
    add("d", 4)
`, Options{})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if strings.Count(r.Source, "rt.MapWithEntry(") != 2 || strings.Count(r.Source, `"add"`) != 2 {
		t.Fatal(r.Source)
	}
}

func TestCollectionPreludeImportedNamesRetainIdentity(t *testing.T) {
	root := t.TempDir()
	for name, source := range map[string]string{
		"local.ms": `export type List[T]:
    value: T
export type Map[K,V]:
    value: V
export type Set[T]:
    value: T
`,
		"main.ms": `import {List,Map,Set} from "./local.ms"
fn f() -> Int: List(1).value + Map[String,Int](2).value + Set(3).value
`,
	} {
		if err := os.WriteFile(filepath.Join(root, name), []byte(source), 0600); err != nil {
			t.Fatal(err)
		}
	}
	r := CompileFile(filepath.Join(root, "main.ms"), Options{})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if strings.Contains(r.Source, "rt.NewCollection(") {
		t.Fatal("application types acquired native constructors")
	}
}
