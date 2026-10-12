package parser_test

import (
	"github.com/manuscript-lang/manuscript/parser"
	"github.com/manuscript-lang/manuscript/syntax"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDesignFixtures(t *testing.T) {
	files, err := filepath.Glob("../tests/e2e/testdata/accept/*.ms")
	if err != nil {
		t.Fatal(err)
	}
	if len(files) < 18 {
		t.Fatal("missing conformance fixtures")
	}
	for _, file := range files {
		t.Run(filepath.Base(file), func(t *testing.T) {
			source, err := os.ReadFile(file)
			if err != nil {
				t.Fatal(err)
			}
			if _, err := parser.Parse(file, string(source)); err != nil {
				t.Fatal(err)
			}
		})
	}
}
func TestRejectSyntax(t *testing.T) {
	for name, source := range map[string]string{
		"module binding":        "let value = 3\n",
		"positional call":       "fn f() -> Unit:\n    g(1)\n",
		"comparison chain":      "fn f() -> Bool:\n    return 1 < 2 < 3\n",
		"two spaces":            "fn f() -> Int:\n  return 1\n",
		"default argument":      "fn f(value: Int = 1) -> Int:\n    return value\n",
		"field assignment":      "fn f() -> Unit:\n    value.field = 1\n",
		"nested named function": "fn f() -> Unit:\n    fn g() -> Unit:\n        return\n",
		"empty type":            "type Empty:\n",
		"mixed type":            "type Mixed:\n    value: Int\n    case Ready\n",
		"bad escape":            "test \"bad\":\n    assert \"\\q\" == \"\"\n",
		"invalid scalar":        "test \"bad\":\n    assert \"\\u{D800}\" == \"\"\n",
		"numeric suffix":        "fn f() -> Int:\n    return 1_000\n",
		"indexing":              "fn f() -> Int:\n    return values[0]\n",
		"single-line lambda":    "fn f() -> Unit:\n    let g = fn() -> Int: 1\n",
		"loop pattern":          "fn f() -> Unit:\n    for [key, value] in entries:\n        return\n",
		"interpolation comment": "fn f() -> String:\n    return \"{1 # comment}\"\n",
		"outer close in lambda": "fn f() -> Unit:\n    consume(transform: fn() -> Unit:\n        return\n        )\n",
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := parser.Parse(name, source); err == nil {
				t.Fatal("accepted invalid syntax")
			}
		})
	}
}

func FuzzParse(f *testing.F) {
	for _, s := range []string{"fn f() -> Unit:\n    return\n", "test \"text\":\n    assert \"{1}\" == \"1\"\n", "type Item:\n    value: Int\n"} {
		f.Add(s)
	}
	f.Fuzz(func(t *testing.T, source string) {
		if len(source) > 16000 {
			t.Skip()
		}
		_, _ = parser.Parse("fuzz.ms", source)
	})
}

func TestNamedArgumentValueContinuation(t *testing.T) {
	source := "fn use(value: Int) -> Unit:\n    return\ntest \"continued argument\":\n    use(value:\n        3\n    )\n"
	if _, err := parser.Parse("continued.ms", source); err != nil {
		t.Fatal(err)
	}
}

func TestInterpolationSpacesAndPhysicalPositions(t *testing.T) {
	source := "fn add(value: Int) -> Int:\r\n    return value\r\nfn render() -> String:\r\n    return \"héllo { add(value: 2) }\"\r\n"
	module, err := parser.Parse("interpolation.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	value := module.Declarations[1].Body[0].Value.Parts[1].Value
	offset := strings.LastIndex(source, "add(value")
	if value.Pos.Offset != offset || value.Args[0].Pos.Offset != offset+4 {
		t.Fatal(value.Pos, value.Args[0].Pos)
	}
	wantColumn := offset - strings.LastIndex(source[:offset], "\n")
	if value.Pos.Line != 4 || value.Pos.Column != wantColumn {
		t.Fatal(value.Pos)
	}
	invalid := "fn render() -> String:\n    return \"hello { @ }\"\n"
	_, err = parser.Parse("interpolation.ms", invalid)
	diagnostic, ok := err.(syntax.Diagnostic)
	if !ok || diagnostic.Position.Line != 2 || diagnostic.Position.Offset != strings.IndexByte(invalid, '@') {
		t.Fatal(err)
	}
}

func TestInterfaceDeclarations(t *testing.T) {
	source := "export interface Read[T: Equal]:\n    fn get() -> T\ntype Box[T]:\n    value: T\nimpl Read[T] for Box[T]:\n    fn get() -> T:\n        return self.value\n"
	module, err := parser.Parse("interface.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	declaration := module.Declarations[0]
	if declaration.Kind != "interface" || !declaration.Export || len(declaration.TypeParams) != 1 || len(declaration.Methods) != 1 {
		t.Fatalf("incorrect interface declaration: %+v", declaration)
	}
	if len(module.Declarations[2].TypeParams) != 0 {
		t.Fatal("impl declares type parameters")
	}
}

func TestRejectInterfaceSyntax(t *testing.T) {
	for name, source := range map[string]string{
		"old contract":      "type Read:\n    fn get() -> Int\n",
		"interface field":   "interface Read:\n    value: Int\n",
		"interface case":    "interface Read:\n    case Ready\n",
		"interface body":    "interface Read:\n    fn get() -> Int:\n        return 1\n",
		"empty interface":   "interface Read:\n",
		"generic operation": "interface Read:\n    fn get[T]() -> T\n",
		"reserved keyword":  "type interface:\n    value: Int\n",
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := parser.Parse(name, source); err == nil {
				t.Fatal("accepted invalid syntax")
			}
		})
	}
}

func TestNamedImports(t *testing.T) {
	for _, source := range []string{
		"import List from \"@std/collections.ms\"\n",
		"import { List } from \"@std/collections.ms\"\n",
		"import { List, Map } from \"@std/collections.ms\"\n",
		"import {\n    List, # first\n    Map,\n} from \"@std/collections.ms\"\n",
	} {
		module, err := parser.Parse("imports.ms", source)
		if err != nil {
			t.Fatal(err)
		}
		want := []string{"List"}
		if strings.Contains(source, "Map") {
			want = append(want, "Map")
		}
		if len(module.Imports) != len(want) {
			t.Fatal(module.Imports)
		}
		for i, name := range want {
			imp := module.Imports[i]
			if imp.Name != name || imp.Path != "@std/collections.ms" || imp.NamePos.Offset != strings.Index(source, name) {
				t.Fatalf("incorrect import: %+v", imp)
			}
		}
	}
}

func TestRejectNamedImports(t *testing.T) {
	for _, source := range []string{
		"import {} from \"./mod.ms\"\n",
		"import { A B } from \"./mod.ms\"\n",
		"import { A,, B } from \"./mod.ms\"\n",
		"import { , A } from \"./mod.ms\"\n",
		"import { A } \"./mod.ms\"\n",
		"import { A } from \"{path}\"\n",
		"import { A as B } from \"./mod.ms\"\n",
		"import A, B from \"./mod.ms\"\n",
	} {
		if _, err := parser.Parse("imports.ms", source); err == nil {
			t.Fatalf("accepted %q", source)
		}
	}
}
