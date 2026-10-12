package parser_test

import (
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDesignFixtures(t *testing.T) {
	files, err := filepath.Glob("../../tests/e2e/testdata/accept/*.ms")
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
		"comparison chain":      "fn f() -> Bool:\n    return 1 < 2 < 3\n",
		"two spaces":            "fn f() -> Int:\n  return 1\n",
		"default function type": "fn f(value: fn(x: Int = 1) -> Int) -> Unit:\n    return\n",
		"default case":          "type F:\n    case Value(value: Int = 1)\n",
		"invalid assignment":    "fn f() -> Unit:\n    (1 + 2) = 1\n",
		"nested named function": "fn f() -> Unit:\n    fn g() -> Unit:\n        return\n",
		"mixed type":            "type Mixed:\n    value: Int\n    case Ready\n",
		"bad escape":            "import panic from \"@std/faults.ms\"\n\ntest \"bad\":\n    if not (\"\\q\" == \"\"):\n        return panic(message: \"check failed\")\n",
		"invalid scalar":        "import panic from \"@std/faults.ms\"\n\ntest \"bad\":\n    if not (\"\\u{D800}\" == \"\"):\n        return panic(message: \"check failed\")\n",
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
	for _, s := range []string{"fn f() -> Unit:\n    return\n", "import panic from \"@std/faults.ms\"\n\ntest \"text\":\n    if not (\"{1}\" == \"1\"):\n        return panic(message: \"check failed\")\n", "type Item:\n    value: Int\n"} {
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

func TestSingleArgumentExpressions(t *testing.T) {
	for _, expression := range []string{"3", "value", "value + 1", "-3", "true", "unit", "\"text\"", "[1, 2]", "other(3)", "(value)", "3,"} {
		t.Run(expression, func(t *testing.T) {
			source := "fn use(value: Int) -> Unit:\n    consume(" + expression + ")\n"
			module, err := parser.Parse("argument.ms", source)
			if err != nil {
				t.Fatal(err)
			}
			call := module.Declarations[0].Body[0].Value
			if len(call.Args) != 1 || call.Args[0].Name != "" || call.Args[0].Pos.Offset != strings.Index(source, expression+")") {
				t.Fatal("incorrect unlabeled argument", call.Args)
			}
		})
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

func TestInlineSuites(t *testing.T) {
	for _, source := range []string{
		"fn double(x: Int) -> Int: return x * 2",
		"fn f() -> Unit: return\nfn g() -> Unit: return\n",
		"fn f(x: Int) -> Int:\n    if x > 0: return x\n    else: return 0\n",
		"fn f(x: Int) -> Int:\n    if x > 0: return x\n    else if x == 0: return 1\n    else:\n        return 2\n",
		"fn f() -> Unit:\n    if true:\n        return\n    else: return\n",
		"fn f() -> Unit:\n    let g = fn(x: Int) -> Int: return x\n    use(fn(x: Int) -> Int: return x, other: 1)\n    let gs = [fn() -> Unit: return, fn() -> Int: return 2]\n",
		"fn f() -> Unit:\n    while true: break\n    for x in values: consume(x)\n    with x = resource(): consume(x)\n",
	} {
		if _, err := parser.Parse("inline.ms", source); err != nil {
			t.Errorf("%s\n%v", source, err)
		}
	}
	for _, source := range []string{
		"fn f() -> Int: 1\n",
		"fn f(x: Int) -> Int:\n    if x > 0: return x else: return 0\n",
		"fn f() -> Unit:\n    if true: return else: return\n",
		"fn f() -> Unit:\n    if true: use() else if false: use()\n",
		"fn f() -> Unit: return return\n",
		"fn f() -> Unit: if true: return\n",
		"fn f() -> Unit:\n    if true: return\n        return\n",
	} {
		if _, err := parser.Parse("inline.ms", source); err == nil {
			t.Errorf("accepted %s", source)
		}
	}
}

func TestMapLiteralBoundaries(t *testing.T) {
	for _, value := range []string{`{}`, `{"a": 1,}`, `{key: {1: 2}}`, `{(fn(value: Int) -> Int: return value): 1}`} {
		source := "fn f() -> Unit:\n    let value = " + value + "\n"
		if _, err := parser.Parse("map.ms", source); err != nil {
			t.Fatal(err)
		}
		if _, diagnostics := parser.ParsePartial("map.ms", source); len(diagnostics) != 0 {
			t.Fatal(diagnostics)
		}
	}
	for _, value := range []string{`{1}`, `{1:}`, `{1: 2 3: 4}`} {
		if _, err := parser.Parse("map.ms", "fn f() -> Unit:\n    let value = "+value+"\n"); err == nil {
			t.Fatal("accepted", value)
		}
	}
}
